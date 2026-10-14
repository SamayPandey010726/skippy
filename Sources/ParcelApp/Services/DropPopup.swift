import AppKit
import ApplicationServices
import SwiftUI

/// The drop popup: a small square that appears on screen the moment a file
/// drag begins anywhere, and vanishes when the drag ends. Drag its top grip
/// to park it anywhere — it remembers its spot. Dropping files starts a new
/// parcel and opens it in the app; the app never opens on hover.
@MainActor final class DropPopupController: NSObject {
  static let shared = DropPopupController()
  private weak var store: ParcelStore?
  private var panel: NSPanel?
  private let enabledKey = "parcel.dropPopupEnabled"
  private let originKey = "parcel-drop-popup-origin"
  private let size: CGFloat = 232
  private var moveBase: CGPoint?
  private var hideWork: DispatchWorkItem?
  private var manualSummon = false

  var isEnabled: Bool {
    get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    set {
      UserDefaults.standard.set(newValue, forKey: enabledKey)
      if !newValue { hide() }
    }
  }

  /// The instant event-driven detection needs Accessibility. The backup poll
  /// works without it, but granting it makes the pop-out immediate.
  var needsAccessibilityGrant: Bool { !AXIsProcessTrusted() }
  func openAccessibilitySettings() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
    }
  }

  func install(store: ParcelStore) {
    self.store = store
    DragMonitor.shared.onDragState = { [weak self] dragging in
      guard let self else { return }
      if dragging { self.showForDrag() } else { self.hide() }
    }
    DragMonitor.shared.start()
  }

  /// ⌃⌥P: summon the popup by hand.
  func togglePopup() {
    if panel?.isVisible == true { hide() } else { summon() }
  }
  func summon() {
    manualSummon = true
    cancelAutoHide()
    showAt(popupOrigin())
    let work = DispatchWorkItem { [weak self] in self?.hide() }
    hideWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
  }

  /// Slide the parked popup with its grip.
  func movePopup(by translation: CGSize) {
    if moveBase == nil { moveBase = panel?.frame.origin }
    guard let base = moveBase else { return }
    panel?.setFrameOrigin(clampOrigin(CGPoint(x: base.x + translation.width,
                                              y: base.y - translation.height)))
  }
  func finishPopupMove() {
    if let origin = panel?.frame.origin { saveOrigin(origin) }
    moveBase = nil
  }

  func handleDrop(_ urls: [URL]) {
    cancelAutoHide()
    hide()
    guard let store, !urls.isEmpty else { return }
    store.dropToNewParcel(urls)
    AppController.shared.openWorkbench()
  }
  func handleTextDrop(_ text: String) {
    cancelAutoHide()
    hide()
    guard let store else { return }
    store.dropTextToNewParcel(text)
    AppController.shared.openWorkbench()
  }

  private func showForDrag() {
    guard isEnabled, store != nil else { return }
    manualSummon = false
    cancelAutoHide()
    showAt(popupOrigin())
  }

  private func showAt(_ origin: CGPoint) {
    ensurePanel()
    guard let p = panel else { return }
    p.setFrameOrigin(origin)
    if p.isVisible { return }
    p.orderFrontRegardless()
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      p.alphaValue = 1
    } else {
      p.alphaValue = 0
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.18
        p.animator().alphaValue = 1
      }
    }
  }

  private func hide() {
    manualSummon = false
    cancelAutoHide()
    guard let p = panel, p.isVisible else { return }
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      p.orderOut(nil)
    } else {
      NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.14
        p.animator().alphaValue = 0
      }, completionHandler: { p.orderOut(nil) })
    }
  }

  private func cancelAutoHide() {
    hideWork?.cancel()
    hideWork = nil
  }

  /// A hovering drag pauses the manual-summon auto-hide.
  func hoverChanged(_ hovering: Bool) {
    guard manualSummon else { return }
    if hovering {
      cancelAutoHide()
    } else if panel?.isVisible == true, hideWork == nil {
      let work = DispatchWorkItem { [weak self] in self?.hide() }
      hideWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }
  }

  private func popupScreen() -> NSScreen {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
      ?? NSScreen.main ?? NSScreen.screens[0]
  }

  private func popupOrigin() -> CGPoint {
    let vf = popupScreen().visibleFrame
    if let saved = loadOrigin(), vf.contains(CGPoint(x: saved.x + size / 2, y: saved.y + size / 2)) {
      return saved
    }
    // First run, or the saved spot is off-screen: centre of this screen.
    return CGPoint(x: vf.midX - size / 2, y: vf.midY - size / 2)
  }

  private func clampOrigin(_ origin: CGPoint) -> CGPoint {
    let vf = popupScreen().visibleFrame
    return CGPoint(
      x: min(max(origin.x, vf.minX), vf.maxX - size),
      y: min(max(origin.y, vf.minY), vf.maxY - size))
  }

  private func loadOrigin() -> CGPoint? {
    guard let s = UserDefaults.standard.string(forKey: originKey) else { return nil }
    let parts = s.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 2 else { return nil }
    return CGPoint(x: parts[0], y: parts[1])
  }
  private func saveOrigin(_ origin: CGPoint) {
    UserDefaults.standard.set("\(origin.x),\(origin.y)", forKey: originKey)
  }

  private func ensurePanel() {
    guard panel == nil, let store else { return }
    let p = NSPanel(
      contentRect: NSRect(origin: .zero, size: NSSize(width: size, height: size)),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.level = .floating
    p.isFloatingPanel = true
    p.hidesOnDeactivate = false
    p.isReleasedWhenClosed = false
    p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    p.backgroundColor = .clear
    p.isOpaque = false
    p.hasShadow = false
    let host = NSHostingView(rootView: DropPopupView().environmentObject(store))
    host.frame = NSRect(origin: .zero, size: NSSize(width: size, height: size))
    host.autoresizingMask = [.width, .height]
    p.contentView = host
    panel = p
  }
}

struct DropPopupView: View {
  @EnvironmentObject private var store: ParcelStore
  @StateObject private var skinStore = SkinStore.shared
  @State private var dropCount = 0
  @State private var hovering = false
  @State private var appeared = false
  @State private var dropBounce = 0
  var body: some View {
    let p = skinStore.skin.palette
    ZStack {
      RoundedRectangle(cornerRadius: 24).fill(p.paper)
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
        .overlay(
          RoundedRectangle(cornerRadius: 24)
            .stroke(hovering ? p.accentSoft.opacity(0.6) : p.line.opacity(0.5), lineWidth: 1))
      VStack(spacing: 9) {
        // Grip — drag to park the popup anywhere on screen.
        RoundedRectangle(cornerRadius: 2)
          .fill(p.secondary.opacity(0.4))
          .frame(width: 40, height: 4)
          .padding(.top, 12)
          .gesture(
            DragGesture()
              .onChanged { DropPopupController.shared.movePopup(by: $0.translation) }
              .onEnded { _ in DropPopupController.shared.finishPopupMove() }
          )
        ParcelIllustration(sealed: false, count: max(dropCount, 1), bounce: dropBounce)
          .frame(width: 104, height: 82)
          .scaleEffect(hovering ? 1.06 : 1)
          .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        Text(
          dropCount > 0
            ? "Drop \(dropCount) file\(dropCount == 1 ? "" : "s")" : "Drop files here"
        )
        .font(.system(size: 14, weight: .semibold)).foregroundStyle(p.accent)
        Text("Give your files somewhere delightful to wait.").font(.system(size: 10))
          .foregroundStyle(p.secondary)
      }.padding(.bottom, 14)
    }
    .scaleEffect(appeared ? 1 : 0.88)
    .opacity(appeared ? 1 : 0)
    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: appeared)
    .onAppear {
      appeared = true
      dropBounce = 0
    }
    .onChange(of: dropCount) { _, new in
      if new > 0 { dropBounce += 1 }
    }
    .frame(width: 232, height: 232)
    .background(
      FileDropSurface(
        enabled: true,
        tap: { AppController.shared.openWorkbench() },
        receive: { DropPopupController.shared.handleDrop($0) },
        receiveText: { DropPopupController.shared.handleTextDrop($0) },
        receiving: { _ in },
        hover: {
          hovering = $0
          DropPopupController.shared.hoverChanged($0)
          if !$0 { dropCount = 0 }
        },
        willReceive: { dropCount = $0.count },
        failure: { store.error = $0 }
      )
    )
  }
}

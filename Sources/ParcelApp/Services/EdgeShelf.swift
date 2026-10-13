import AppKit
import SwiftUI

/// The drop shelf: a slim tab docked at the right screen edge, always on top.
/// Drag files onto it and it slides out; dropping makes a parcel at once and
/// opens it in the app. No floating window needed.
@MainActor final class EdgeShelfController: NSObject {
  static let shared = EdgeShelfController()
  private weak var store: ParcelStore?
  private var panel: NSPanel?
  private let visibleKey = "parcel.edgeShelfVisible"
  private let shelfWidth: CGFloat = 336
  private let shelfHeight: CGFloat = 400
  /// The docked trigger is a whisper of an edge strip — the shelf itself only
  /// appears while files hover it.
  private let tabWidth: CGFloat = 5

  func install(store: ParcelStore) {
    self.store = store
    if isShelfVisible() { show() }
  }
  func isShelfVisible() -> Bool {
    UserDefaults.standard.object(forKey: visibleKey) as? Bool ?? true
  }
  func setShelfVisible(_ visible: Bool) {
    UserDefaults.standard.set(visible, forKey: visibleKey)
    if visible { show() } else { hide() }
  }
  func toggle() { setShelfVisible(!isShelfVisible()) }
  func show() {
    UserDefaults.standard.set(true, forKey: visibleKey)
    ensurePanel()
    panel?.setFrame(dockedFrame(), display: true)
    panel?.orderFront(nil)
  }
  func hide() {
    UserDefaults.standard.set(false, forKey: visibleKey)
    panel?.orderOut(nil)
  }
  /// Slides the shelf out while a drag hovers it, back when the drag leaves.
  func setExpanded(_ expanded: Bool) {
    guard let p = panel, p.isVisible else { return }
    let target = expanded ? revealedFrame() : dockedFrame()
    guard p.frame != target else { return }
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.25
      p.animator().setFrame(target, display: true)
    }
  }
  func handleDrop(_ urls: [URL]) {
    setExpanded(false)
    guard let store, !urls.isEmpty else { return }
    // The app opens only on drop — never while hovering.
    store.dropToNewParcel(urls)
    AppController.shared.openWorkbench()
  }
  func handleTextDrop(_ text: String) {
    setExpanded(false)
    guard let store else { return }
    store.dropTextToNewParcel(text)
    AppController.shared.openWorkbench()
  }
  private func targetScreen() -> NSScreen {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
      ?? NSScreen.main ?? NSScreen.screens[0]
  }
  private func dockedFrame() -> NSRect {
    let vf = targetScreen().visibleFrame
    return NSRect(
      x: vf.maxX - tabWidth, y: vf.midY - shelfHeight / 2, width: shelfWidth, height: shelfHeight)
  }
  private func revealedFrame() -> NSRect {
    let vf = targetScreen().visibleFrame
    return NSRect(
      x: vf.maxX - shelfWidth, y: vf.midY - shelfHeight / 2, width: shelfWidth, height: shelfHeight)
  }
  private func ensurePanel() {
    guard panel == nil, let store else { return }
    let p = NSPanel(
      contentRect: NSRect(origin: .zero, size: NSSize(width: shelfWidth, height: shelfHeight)),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.level = .floating
    p.isFloatingPanel = true
    p.hidesOnDeactivate = false
    p.isReleasedWhenClosed = false
    p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    p.backgroundColor = .clear
    p.isOpaque = false
    p.hasShadow = false
    let host = NSHostingView(rootView: EdgeShelfView().environmentObject(store))
    host.frame = NSRect(origin: .zero, size: NSSize(width: shelfWidth, height: shelfHeight))
    host.autoresizingMask = [.width, .height]
    p.contentView = host
    panel = p
  }
}

struct EdgeShelfView: View {
  @EnvironmentObject private var store: ParcelStore
  @State private var dropCount = 0
  var body: some View {
    HStack(spacing: 0) {
      // The trigger: a whisper of an edge strip. The shelf itself only
      // appears while files hover it.
      RoundedRectangle(cornerRadius: 2.5)
        .fill(Ink.green.opacity(0.45))
        .frame(width: 5)
        .padding(.vertical, 10)
      // The drop area, revealed on hover.
      ZStack {
        Ink.paper
        VStack(spacing: 13) {
          ParcelIllustration(sealed: false, count: max(dropCount, 1), bounce: 0)
            .frame(width: 150, height: 118)
          Text(dropCount > 0 ? "Drop \(dropCount) file\(dropCount == 1 ? "" : "s")" : "Drop files here")
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Ink.green)
          Text("A new parcel starts instantly\nand opens in the app, ready to pack.")
            .font(.system(size: 11)).foregroundStyle(Ink.secondary)
            .multilineTextAlignment(.center).lineSpacing(3)
          Text("or click to open Parcel").font(.system(size: 10)).foregroundStyle(
            Ink.secondary.opacity(0.75))
        }.padding(26)
      }
    }
    .frame(width: 336, height: 400)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
    .background(
      FileDropSurface(
        enabled: true,
        tap: { AppController.shared.openWorkbench() },
        receive: { EdgeShelfController.shared.handleDrop($0) },
        receiveText: { EdgeShelfController.shared.handleTextDrop($0) },
        receiving: { _ in },
        hover: {
          EdgeShelfController.shared.setExpanded($0)
          if !$0 { dropCount = 0 }
        },
        willReceive: { dropCount = $0.count },
        failure: { store.error = $0 }
      )
    )
  }
}

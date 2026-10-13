import AppKit
import SwiftUI

/// The drop shelf: a whisper of an edge strip, always on top.
/// It pops out on its own the moment a file drag begins anywhere on screen,
/// or when a drag hovers the strip; the app itself opens only on drop.
@MainActor final class EdgeShelfController: NSObject {
  static let shared = EdgeShelfController()
  private weak var store: ParcelStore?
  private var panel: NSPanel?
  private let visibleKey = "parcel.edgeShelfVisible"
  private let edgeKey = "parcel-shelf-edge"
  private let offsetKey = "parcel-shelf-offset"
  private let shelfWidth: CGFloat = 336
  private let shelfHeight: CGFloat = 400
  private let tabWidth: CGFloat = 5
  private var offsetY: CGFloat = 0
  private var dragBase: CGFloat?
  private var expanded = false

  enum Edge: String, CaseIterable {
    case left, right
    var label: String { rawValue.capitalized }
  }
  var edge: Edge {
    get { Edge(rawValue: UserDefaults.standard.string(forKey: edgeKey) ?? "") ?? .right }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: edgeKey)
      layout()
    }
  }

  func install(store: ParcelStore) {
    self.store = store
    offsetY = CGFloat(UserDefaults.standard.double(forKey: offsetKey))
    if isShelfVisible() { show() }
    // Auto pop-out: any file drag anywhere on screen reveals the shelf.
    DragMonitor.shared.onDragState = { [weak self] dragging in
      guard let self, self.isShelfVisible() else { return }
      self.setExpanded(dragging)
    }
    DragMonitor.shared.start()
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
  /// Slides the shelf out while files hover, back when the drag leaves.
  func setExpanded(_ expanded: Bool) {
    guard let p = panel, p.isVisible else { return }
    self.expanded = expanded
    let target = expanded ? revealedFrame() : dockedFrame()
    guard p.frame != target else { return }
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      p.setFrame(target, display: true)
      return
    }
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.38
      ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
      p.animator().setFrame(target, display: true)
    }
  }
  /// Drag the shelf's grip to slide it up or down the edge.
  func nudgeShelf(by dy: CGFloat) {
    if dragBase == nil { dragBase = offsetY }
    offsetY = clampOffset((dragBase ?? 0) + dy)
    layout()
  }
  func finishShelfDrag() {
    dragBase = nil
    UserDefaults.standard.set(Double(offsetY), forKey: offsetKey)
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
  private func layout() {
    guard let p = panel, p.isVisible else { return }
    p.setFrame(expanded ? revealedFrame() : dockedFrame(), display: true)
  }
  private func clampOffset(_ value: CGFloat) -> CGFloat {
    let vf = targetScreen().visibleFrame
    let limit = max(0, vf.height / 2 - shelfHeight / 2 - 8)
    return min(limit, max(-limit, value))
  }
  private func targetScreen() -> NSScreen {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
      ?? NSScreen.main ?? NSScreen.screens[0]
  }
  private func baseY() -> CGFloat {
    let vf = targetScreen().visibleFrame
    return max(vf.minY + 8, min(vf.maxY - shelfHeight - 8, vf.midY + offsetY - shelfHeight / 2))
  }
  private func dockedFrame() -> NSRect {
    let vf = targetScreen().visibleFrame
    let x = edge == .right ? vf.maxX - tabWidth : vf.minX
    return NSRect(x: x, y: baseY(), width: shelfWidth, height: shelfHeight)
  }
  private func revealedFrame() -> NSRect {
    let vf = targetScreen().visibleFrame
    let x = edge == .right ? vf.maxX - shelfWidth : vf.minX
    return NSRect(x: x, y: baseY(), width: shelfWidth, height: shelfHeight)
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
      // appears while files are dragged.
      RoundedRectangle(cornerRadius: 2.5)
        .fill(Ink.green.opacity(0.45))
        .frame(width: 5)
        .padding(.vertical, 10)
      // The drop area, revealed on hover.
      ZStack {
        Ink.paper
        VStack(spacing: 13) {
          // Grip: drag to slide the shelf up or down the edge.
          RoundedRectangle(cornerRadius: 2)
            .fill(Ink.secondary.opacity(0.35))
            .frame(width: 38, height: 4)
            .padding(.top, 10)
            .gesture(
              DragGesture()
                .onChanged { EdgeShelfController.shared.nudgeShelf(by: $0.translation.height) }
                .onEnded { _ in EdgeShelfController.shared.finishShelfDrag() }
            )
          ParcelIllustration(sealed: false, count: max(dropCount, 1), bounce: 0)
            .frame(width: 150, height: 118)
          Text(
            dropCount > 0
              ? "Drop \(dropCount) file\(dropCount == 1 ? "" : "s")" : "Drop files here"
          )
          .font(.system(size: 15, weight: .semibold)).foregroundStyle(Ink.green)
          Text("A new parcel starts instantly\nand opens in the app, ready to pack.")
            .font(.system(size: 11)).foregroundStyle(Ink.secondary)
            .multilineTextAlignment(.center).lineSpacing(3)
          Text("or click to open Parcel").font(.system(size: 10)).foregroundStyle(
            Ink.secondary.opacity(0.75))
        }.padding(.horizontal, 26).padding(.bottom, 26)
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

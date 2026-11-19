import AppKit
import SwiftUI

@MainActor final class CourierMenuBar: NSObject {
  static let shared = CourierMenuBar()
  private var item: NSStatusItem?
  private var travelling: NSPanel?
  func install(store: ParcelStore) {
    guard item == nil else { return }
    let status = NSStatusBar.system.statusItem(withLength: 30)
    if let button = status.button {
      button.image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "Parcels")
      button.toolTip = "Parcels — click or hover to open"
      let receiver = Receiver(frame: button.bounds)
      receiver.autoresizingMask = [.width, .height]
      receiver.registerForDraggedTypes([.fileURL, .png, .tiff, .URL] + NSFilePromiseReceiver.readableDraggedTypes.map { .init($0) })
      button.addSubview(receiver)
    }
    item = status
  }
  private var screenFrame: CGRect? {
    guard let button = item?.button, let window = button.window else { return nil }
    return window.convertToScreen(button.convert(button.bounds, to: nil))
  }
  func parkAnimation(from frame: CGRect?, count: Int, completion: @escaping () -> Void) {
    animate(from: frame, to: screenFrame, count: count, returning: false, completion: completion)
  }
  func returnAnimation(to frame: CGRect?, count: Int, completion: @escaping () -> Void) {
    animate(from: screenFrame, to: frame, count: count, returning: true, completion: completion)
  }
  private func animate(from start: CGRect?, to end: CGRect?, count: Int, returning: Bool, completion: @escaping () -> Void) {
    travelling?.close()
    travelling = nil
    guard let start, let end, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { completion(); return }
    let ghost = NSPanel(contentRect: start, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    ghost.level = .statusBar
    ghost.isReleasedWhenClosed = false
    ghost.backgroundColor = .clear; ghost.isOpaque = false; ghost.ignoresMouseEvents = true
    ghost.contentView = NSHostingView(rootView: CourierSatchel(count: count, skin: SkinStore.shared.skin).padding(5))
    ghost.alphaValue = returning ? 0.15 : 1
    travelling = ghost
    ghost.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.24
      ghost.animator().setFrame(end, display: true)
      ghost.animator().alphaValue = returning ? 1 : 0.15
    }, completionHandler: {
      MainActor.assumeIsolated {
        ghost.close()
        if self.travelling === ghost { self.travelling = nil }
        completion()
      }
    })
  }
  final class Receiver: FileDropSurface.ReceivingView {
    private var area: NSTrackingArea?
    override init(frame: NSRect) {
      super.init(frame: frame)
      tap = { DropPopupController.shared.toggleMenuBar() }
      beginDrop = { DropPopupController.shared.beginPrimaryDrop() }
      hover = { [weak self] inside in self?.hoverCourier(inside) }
      dragHover = { [weak self] inside in
        self?.hoverCourier(inside, dragging: true)
      }
      setAccessibilityLabel("Parcels in the menu bar")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      if let area { removeTrackingArea(area) }
      let next = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .enabledDuringMouseDrag], owner: self)
      addTrackingArea(next); area = next
      beginDrop = { DropPopupController.shared.beginPrimaryDrop() }
      hover = { [weak self] inside in self?.hoverCourier(inside) }
      tap = { DropPopupController.shared.toggleMenuBar() }
    }
    private func hoverCourier(_ inside: Bool, dragging: Bool = false) {
      guard let window else { return }
      DropPopupController.shared.menuHover(inside, anchor: window.convertToScreen(convert(bounds, to: nil)), dragging: dragging)
    }
    override func mouseEntered(with event: NSEvent) { hoverCourier(true) }
    override func mouseExited(with event: NSEvent) { hoverCourier(false) }
    override func rightMouseDown(with event: NSEvent) {
      let menu = NSMenu()
      for (title, action) in [("Open Parcels", #selector(restoreCourier)),
                              ("Parcels settings…", #selector(openSettings)),
                              ("Quit Parcels", #selector(quitParcel))] {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; menu.addItem(item)
      }
      NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc private func restoreCourier() { DropPopupController.shared.summon() }
    @objc private func openSettings() { AppController.shared.openPreferences() }
    @objc private func quitParcel() { NSApp.terminate(nil) }
  }
}

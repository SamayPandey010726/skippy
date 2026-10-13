import AppKit
import Carbon
import ParcelCore
import SwiftUI

@MainActor final class AppController: NSObject {
  static let shared = AppController()
  private weak var store: ParcelStore?
  private var panel: NSPanel?
  private var hotKey: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  var showWorkbench: (() -> Void)?
  private let pinKey = "parcel.panelPinned"
  private let originKey = "parcel.panelOrigin"
  /// Whether the floating folder sticks to the screen edge.
  func isPinned() -> Bool { UserDefaults.standard.bool(forKey: pinKey) }
  func setPinned(_ pinned: Bool) {
    UserDefaults.standard.set(pinned, forKey: pinKey)
    guard pinned, let p = panel, let screen = p.screen ?? NSScreen.main else { return }
    let vf = screen.visibleFrame
    p.setFrameOrigin(NSPoint(x: vf.maxX - p.frame.width, y: vf.midY - p.frame.height / 2))
  }
  private func placePanel(_ p: NSPanel) {
    if let saved = UserDefaults.standard.string(forKey: originKey) {
      p.setFrameOrigin(NSPointFromString(saved))
    } else {
      p.center()
    }
    if isPinned(), let screen = p.screen ?? NSScreen.main {
      let vf = screen.visibleFrame
      p.setFrameOrigin(NSPoint(x: vf.maxX - p.frame.width, y: vf.midY - p.frame.height / 2))
    }
  }
  private func watchPanelMovement(_ p: NSPanel) {
    NotificationCenter.default.addObserver(
      forName: NSWindow.didMoveNotification, object: p, queue: .main
    ) { [weak self, weak p] _ in
      guard let self, let p else { return }
      self.snapAndRemember(p)
    }
  }
  private func snapAndRemember(_ p: NSPanel) {
    guard let screen = p.screen ?? NSScreen.main else { return }
    let vf = screen.visibleFrame
    var origin = p.frame.origin
    let d: CGFloat = 24
    if abs(p.frame.minX - vf.minX) < d { origin.x = vf.minX }
    if abs(vf.maxX - p.frame.maxX) < d { origin.x = vf.maxX - p.frame.width }
    if abs(vf.maxY - p.frame.maxY) < d { origin.y = vf.maxY - p.frame.height }
    if abs(p.frame.minY - vf.minY) < d { origin.y = vf.minY }
    if origin != p.frame.origin { p.setFrameOrigin(origin) }
    UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: originKey)
  }
  func install(store: ParcelStore) {
    self.store = store
    guard hotKey == nil else { return }
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, _ in
        Task { @MainActor in AppController.shared.togglePanel() }
        return noErr
      }, 1, &spec, nil, &eventHandler)
    let id = EventHotKeyID(signature: 0x5052_434C, id: 1)
    RegisterEventHotKey(
      UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0,
      &hotKey)
  }
  func togglePanel() {
    guard let store else { return }
    if let panel, panel.isVisible {
      panel.orderOut(nil)
      return
    }
    if panel == nil {
      let p = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 590),
        styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow], backing: .buffered,
        defer: false)
      p.title = "Parcel"
      p.titlebarAppearsTransparent = true
      p.titleVisibility = .hidden
      p.isFloatingPanel = true
      p.level = .floating
      p.hidesOnDeactivate = false
      p.isReleasedWhenClosed = false
      p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      p.backgroundColor = NSColor(red: 0.98, green: 0.965, blue: 0.92, alpha: 1)
      p.contentView = NSHostingView(rootView: CompactParcelView().environmentObject(store))
      placePanel(p)
      watchPanelMovement(p)
      panel = p
    }
    panel?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  func openWorkbench() {
    showWorkbench?()
    NSApp.activate(ignoringOtherApps: true)
  }
  func hidePanel() { panel?.orderOut(nil) }
}

@MainActor final class ParcelAppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let store = ParcelRuntime.store, store.busy else { return .terminateNow }
    let alert = NSAlert()
    alert.messageText = "A parcel is still being prepared."
    alert.informativeText =
      "Wait for it to finish, or cancel the operation in Parcel before quitting. Your originals are safe."
    alert.addButton(withTitle: "Keep Parcel open")
    alert.runModal()
    return .terminateCancel
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func application(_ application: NSApplication, open urls: [URL]) {
    ParcelRuntime.receive(urls)
    AppController.shared.openWorkbench()
  }
}
@MainActor enum ParcelRuntime {
  private static var pendingURLs: [URL] = []
  static weak var store: ParcelStore? {
    didSet {
      guard let store, !pendingURLs.isEmpty else { return }
      let urls = pendingURLs
      pendingURLs.removeAll()
      store.ingest(urls)
    }
  }
  static func receive(_ urls: [URL]) {
    if let store { store.ingest(urls) } else { pendingURLs.append(contentsOf: urls) }
  }
}

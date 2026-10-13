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
      p.center()
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

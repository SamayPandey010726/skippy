import AppKit
import Carbon
import ParcelCore
import SwiftUI

@MainActor final class AppController: NSObject {
  static let shared = AppController()
  private weak var store: ParcelStore?
  private var hotKey: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  var showWorkbench: (() -> Void)?
  func install(store: ParcelStore) {
    self.store = store
    DropPopupController.shared.install(store: store)
    DockPickerController.shared.install(store: store)
    DragMonitor.shared.onDragState = { dragging in
      if !dragging { DockPickerController.shared.hide() }
    }
    guard hotKey == nil else { return }
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, _ in
        Task { @MainActor in AppController.shared.toggleDropPopup() }
        return noErr
      }, 1, &spec, nil, &eventHandler)
    let id = EventHotKeyID(signature: 0x5052_434C, id: 1)
    RegisterEventHotKey(
      UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0,
      &hotKey)
  }
  /// The drop popup appears on screen while files are dragged; ⌃⌥P summons it by hand.
  func toggleDropPopup() { DropPopupController.shared.togglePopup() }
  /// Dock menu: open a parcel item directly.
  @objc nonisolated func openDockItem(_ sender: NSMenuItem) {
    if let path = sender.representedObject as? String {
      DispatchQueue.main.async {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
      }
    }
  }
  func openWorkbench() {
    showWorkbench?()
    NSApp.activate(ignoringOtherApps: true)
  }
}

@MainActor final class ParcelAppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    // Clicking the Dock icon with no windows open must bring the app back.
    if !flag { AppController.shared.openWorkbench() }
    return true
  }
  func applicationDidBecomeActive(_ notification: Notification) {
    // Spring Loading: the user dragged a file over Parcel's Dock icon and
    // held it. Show the picker near the Dock so they can drop into a
    // parcel without opening the app window.
    if DragMonitor.shared.isDragging {
      DockPickerController.shared.show()
    }
  }
  func applicationDidResignActive(_ notification: Notification) {
    DockPickerController.shared.hide()
  }
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
  /// Right-click the Dock icon: packed parcels fan out, anything opens directly.
  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    guard let store = ParcelRuntime.store, !store.recentParcels.isEmpty else { return nil }
    let menu = NSMenu()
    for box in store.recentParcels.prefix(6) {
      let sub = NSMenu()
      for item in box.items.prefix(15) {
        let mi = NSMenuItem(
          title: item.displayName, action: #selector(AppController.openDockItem(_:)),
          keyEquivalent: "")
        mi.target = AppController.shared
        mi.representedObject = item.effectiveURL.path
        sub.addItem(mi)
      }
      let mi = NSMenuItem(title: box.name, action: nil, keyEquivalent: "")
      mi.submenu = sub
      menu.addItem(mi)
    }
    return menu
  }
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

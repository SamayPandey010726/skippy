import AppKit
import SwiftUI

@main @MainActor struct ParcelApp: App {
  @NSApplicationDelegateAdaptor(ParcelAppDelegate.self) private var delegate
  @StateObject private var store = ParcelStore()
  var body: some Scene {
    Window("Parcel", id: "workbench") {
      WorkbenchView().environmentObject(store).frame(minWidth: 980, minHeight: 700)
        .onAppear {
          ParcelRuntime.store = store
          AppController.shared.install(store: store)
          store.checkCacheOnStartup()
        }
    }
    .windowStyle(.hiddenTitleBar).defaultSize(width: 1160, height: 820)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("New parcel") { store.newBox() }.keyboardShortcut("n").disabled(store.busy)
        Button("Add files…") { store.addFilesPanel() }.keyboardShortcut("o").disabled(store.busy)
        Button("Paste into parcel") { store.paste() }.keyboardShortcut(
          "v", modifiers: [.command, .shift]
        ).disabled(store.busy)
      }
      CommandMenu("Parcel") {
        Button("Pack ZIP") { store.seal() }.keyboardShortcut("p", modifiers: [.command, .shift])
          .disabled(store.busy || store.items.isEmpty || !store.canExport)
        Button("Prepare images…") { store.showPrepare = true }.keyboardShortcut("e").disabled(
          store.imageItems.isEmpty || store.busy || !store.canExport)
        Button("Copy contents list") { store.copyManifest() }.keyboardShortcut(
          "c", modifiers: [.command, .shift])
        Button("Show drop shelf") { AppController.shared.toggleShelf() }.keyboardShortcut(
          "p", modifiers: [.control, .option])
        Divider()
        Button("Share via WhatsApp") { store.shareViaWhatsApp() }.disabled(
          store.busy || !store.canExport)
        Divider()
        Button("Select all pieces") { store.selectAll() }.keyboardShortcut("a")
        Button("Remove selected pieces") { store.remove(store.selectedItems) }.keyboardShortcut(
          .delete, modifiers: [.command]
        ).disabled(store.selectedItems.isEmpty || store.busy)
      }
    }
    MenuBarExtra("Parcel", systemImage: "folder") {
      Button("Open Parcel") { AppController.shared.openWorkbench() }
      Button("Drop shelf    ⌃⌥P") { AppController.shared.toggleShelf() }
      Button("Add files…") { store.addFilesPanel() }.disabled(store.busy)
      Button("Paste into parcel") { store.paste() }.disabled(store.busy)
      Divider()
      ForEach(store.boxes.prefix(8)) { box in
        Button(box.name) {
          store.selectBox(box.id)
          AppController.shared.openWorkbench()
        }.disabled(store.busy)
      }
      Divider()
      SettingsLink()
      Button("Quit Parcel") { NSApp.terminate(nil) }
    }
    Settings { PreferencesView().environmentObject(store).frame(width: 550, height: 540) }
  }
}

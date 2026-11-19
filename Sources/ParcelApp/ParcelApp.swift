import AppKit
import SwiftUI

extension Notification.Name {
  static let parcelFocusSearch = Notification.Name("parcel-focus-search")
  static let parcelFocusCourierSearch = Notification.Name("parcel-focus-courier-search")
  static let parcelShowCourierFilters = Notification.Name("parcel-show-courier-filters")
  static let parcelFocusClipboardSearch = Notification.Name("parcel-focus-clipboard-search")
}

@main @MainActor struct ParcelApp: App {
  @NSApplicationDelegateAdaptor(ParcelAppDelegate.self) private var delegate
  @StateObject private var store = ParcelRuntime.store

  init() { ParcelShortcuts.updateAppShortcutParameters() }

  var body: some Scene {
    MenuBarExtra("Skippy", systemImage: "square.grid.2x2.fill", isInserted: .constant(false)) { EmptyView() }
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings…") { AppController.shared.openPreferences() }.keyboardShortcut(",")
      }
      CommandGroup(replacing: .newItem) {
        Button("Add files…") { store.addFilesPanel() }.keyboardShortcut("o").disabled(store.busy || !store.license.canUseApp)
        Button("Paste into parcel") { store.paste() }
          .keyboardShortcut("v", modifiers: [.command, .shift]).disabled(store.busy || !store.license.canUseApp)
      }
      CommandMenu("Go") {
        Button("Focus search") {
          NotificationCenter.default.post(name: .parcelFocusSearch, object: nil)
        }.keyboardShortcut("f").disabled(!store.license.canUseApp)
      }
      CommandMenu("Skippy") {
        Button("Pack \(store.packaging.format.label)") { store.seal() }
          .keyboardShortcut("p", modifiers: [.command, .shift])
          .disabled(store.busy || store.items.isEmpty || !store.canExport)
        Button("Prepare images…") {
          if AppController.shared.isWorkbenchVisible { store.showPrepare = true }
          else { DropPopupController.shared.presentMediaEditor() }
        }.keyboardShortcut("e")
          .disabled(store.imageItems.isEmpty || store.busy || !store.canExport)
        Button("Prepare videos…") {
          if AppController.shared.isWorkbenchVisible { store.showVideoPrepare = true }
          else { DropPopupController.shared.presentMediaEditor() }
        }
          .disabled(store.videoItems.isEmpty || store.busy || !store.canExport)
        Button("Transform PDF or image…") {
          if AppController.shared.isWorkbenchVisible { store.showTransform = true }
          else { DropPopupController.shared.presentMediaEditor() }
        }.keyboardShortcut("t", modifiers: [.command, .shift])
          .disabled(store.availableTransforms.isEmpty || store.busy || !store.canExport)
        Button("Copy image text with OCR") { store.extractTextFromImages() }
          .keyboardShortcut("o", modifiers: [.command, .shift])
          .disabled(store.imageItems.isEmpty || store.busy || store.extractingText || !store.canExport)
        Button("Copy contents list") { store.copyManifest() }
          .keyboardShortcut("c", modifiers: [.command, .shift]).disabled(!store.canExport)
        Button("Copy local file link") { store.copyArchiveLink() }
          .disabled(!store.ready || store.busy || !store.canExport)
        Button("Open Skippy") { AppController.shared.toggleDropPopup() }
        Divider()
        Button("Share via WhatsApp") { store.shareViaWhatsApp() }.disabled(store.busy || !store.canExport)
        Divider()
        Button("Select all pieces") {
          if let editor = NSApp.keyWindow?.firstResponder as? NSTextView { editor.selectAll(nil) }
          else { store.selectAll() }
        }.keyboardShortcut("a")
          .disabled(!store.canExport)
        Button("Pin/unpin selected pieces") { store.togglePinSelected() }
          .keyboardShortcut("p", modifiers: [.command, .option])
          .disabled(store.selectedItems.isEmpty || store.busy || !store.canExport)
        Button("Remove selected pieces") { store.remove(store.selectedItems) }
          .keyboardShortcut(.delete, modifiers: [.command])
          .disabled(store.selectedItems.isEmpty || store.busy || !store.canExport)
      }
    }
  }
}

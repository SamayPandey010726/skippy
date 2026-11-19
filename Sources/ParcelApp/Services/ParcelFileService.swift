import AppKit

@MainActor final class ParcelFileService: NSObject {
  static let shared = ParcelFileService()
  private weak var store: ParcelStore?
  func install(store: ParcelStore) {
    self.store = store
    NSApp.servicesProvider = self
    NSUpdateDynamicServices()
  }
  static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
    if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
      !urls.isEmpty { return urls.filter(\.isFileURL) }
    let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] ?? []
    return paths.map { URL(fileURLWithPath: $0) }
  }
  @objc func sendToParcels(_ pasteboard: NSPasteboard, userData: String?,
    error: AutoreleasingUnsafeMutablePointer<NSString?>) {
    let urls = Self.fileURLs(from: pasteboard)
    guard !urls.isEmpty else { error.pointee = "Select files or folders to send to Parcels."; return }
    guard let store, !store.busy, store.phase != .receiving, !store.needsLibraryRecovery else {
      error.pointee = "Parcel is busy or its library needs recovery. Try again when it is ready."; return
    }
    let shelf = DropPopupController.shared
    shelf.summon()
    guard let handler = shelf.beginPrimaryDrop() else { error.pointee = "Parcel could not accept these files."; return }
    handler.receive(urls)
  }
}

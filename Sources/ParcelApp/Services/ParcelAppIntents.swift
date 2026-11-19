import AppIntents
import Foundation
import ParcelCore

private enum ParcelIntentError: LocalizedError {
  case unavailable(String)
  var errorDescription: String? {
    switch self { case .unavailable(let message): return message }
  }
}

struct SummonParcelCourierIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Skippy"
  static let description = IntentDescription("Opens the Skippy widget dashboard at the top of the screen.")
  static var openAppWhenRun = false

  @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
    DropPopupController.shared.summon()
    return .result(dialog: "Skippy is open.")
  }
}

struct AddFilesToParcelIntent: AppIntent {
  static let title: LocalizedStringResource = "Add Files to File Shelf"
  static let description = IntentDescription("Adds files to your parcel.")
  static var openAppWhenRun = false

  @Parameter(title: "Files") var files: [IntentFile]

  @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
    let urls = files.compactMap(\.fileURL)
    guard !urls.isEmpty else { throw ParcelIntentError.unavailable("Choose at least one local file.") }
    guard let destination = ParcelRuntime.store.current?.id ?? ParcelRuntime.store.boxes.first?.id else {
      throw ParcelIntentError.unavailable("Your parcel is unavailable.")
    }
    let before = ParcelRuntime.store.boxes.first(where: { $0.id == destination })?.items.count ?? 0
    ParcelRuntime.store.ingest(urls, into: destination)
    let after = ParcelRuntime.store.boxes.first(where: { $0.id == destination })?.items.count ?? before
    let added = max(0, after - before)
    return .result(dialog: "Added \(added) file\(added == 1 ? "" : "s") to File Shelf.")
  }
}

struct PackParcelIntent: AppIntent {
  static let title: LocalizedStringResource = "Pack Parcel"
  static let description = IntentDescription("Packs your parcel and returns the archive.")
  static var openAppWhenRun = false

  @MainActor func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
    let store = ParcelRuntime.store
    if let parcel = store.current?.id ?? store.boxes.first?.id, store.selectedBox != parcel { store.selectBox(parcel) }
    guard !store.items.isEmpty else { throw ParcelIntentError.unavailable("The parcel is empty.") }
    let archive = await withCheckedContinuation { continuation in
      store.seal(finished: { continuation.resume(returning: $0) })
    }
    guard let archive else { throw ParcelIntentError.unavailable(store.error ?? "The parcel could not be packed.") }
    return .result(value: IntentFile(fileURL: archive), dialog: "Parcel packed and ready.")
  }
}

struct SearchParcelsIntent: AppIntent {
  static let title: LocalizedStringResource = "Search Skippy"
  static let description = IntentDescription("Opens Skippy and searches parcel names and file metadata.")
  static var openAppWhenRun = true

  @Parameter(title: "Search") var query: String

  @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
    ParcelRuntime.store.searchText = query
    DropPopupController.shared.summon()
    DropPopupController.shared.showSearch()
    return .result(dialog: "Searching Skippy for \(query).")
  }
}

struct ParcelShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: SummonParcelCourierIntent(),
      phrases: ["Open \(.applicationName)", "Show \(.applicationName) widgets"],
      shortTitle: "Open Skippy", systemImageName: "square.grid.2x2")
    AppShortcut(
      intent: AddFilesToParcelIntent(),
      phrases: ["Add files to \(.applicationName)", "Put files in my \(.applicationName) parcel"],
      shortTitle: "Add Files", systemImageName: "doc.badge.plus")
    AppShortcut(
      intent: PackParcelIntent(),
      phrases: ["Pack my \(.applicationName) parcel", "Seal my parcel with \(.applicationName)"],
      shortTitle: "Pack Parcel", systemImageName: "archivebox")
    AppShortcut(
      intent: SearchParcelsIntent(),
      phrases: ["Search my \(.applicationName) parcels", "Find files in \(.applicationName)"],
      shortTitle: "Search Skippy", systemImageName: "magnifyingglass")
  }

  static var shortcutTileColor: ShortcutTileColor { .orange }
}

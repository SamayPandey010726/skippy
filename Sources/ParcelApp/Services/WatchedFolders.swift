import AppKit
import Darwin
import Foundation
import ParcelCore

enum WatchedFolderRule: String, Codable, CaseIterable {
  case all
  case downloads
  case screenshots
  var label: String {
    switch self {
    case .all: return "All completed files"
    case .downloads: return "Completed downloads"
    case .screenshots: return "Screenshots only"
    }
  }
}

struct WatchedFolder: Codable, Identifiable, Equatable {
  var id = UUID()
  var path: String
  var bookmark: Data?
  var parcelID: UUID
  var enabled = true
  var knownNames: Set<String>
  var rule: WatchedFolderRule = .all
  private enum CodingKeys: String, CodingKey { case id, path, bookmark, parcelID, enabled, knownNames, rule }
  init(id: UUID = UUID(), path: String, bookmark: Data?, parcelID: UUID, enabled: Bool = true,
       knownNames: Set<String>, rule: WatchedFolderRule = .all) {
    self.id = id; self.path = path; self.bookmark = bookmark; self.parcelID = parcelID
    self.enabled = enabled; self.knownNames = knownNames; self.rule = rule
  }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    path = try values.decode(String.self, forKey: .path)
    bookmark = try values.decodeIfPresent(Data.self, forKey: .bookmark)
    parcelID = try values.decode(UUID.self, forKey: .parcelID)
    enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    knownNames = try values.decodeIfPresent(Set<String>.self, forKey: .knownNames) ?? []
    rule = try values.decodeIfPresent(WatchedFolderRule.self, forKey: .rule) ?? .all
  }
}

struct WatchedEntry: Equatable, Sendable {
  var name: String
  var bytes: Int64
  var modified: Date
  var directory: Bool
}

enum WatchedFolderScan {
  static let temporaryExtensions: Set<String> = ["download", "crdownload", "part", "partial", "tmp"]
  static func entries(at folder: URL, rule: WatchedFolderRule = .all) throws -> [WatchedEntry] {
    try FileManager.default.contentsOfDirectory(at: folder,
      includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
      options: [.skipsHiddenFiles]).compactMap { url in
        guard !temporaryExtensions.contains(url.pathExtension.lowercased()), includes(url, rule: rule) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else { return nil }
        return WatchedEntry(name: url.lastPathComponent, bytes: Int64(values.fileSize ?? 0),
          modified: values.contentModificationDate ?? .distantPast, directory: values.isDirectory == true)
      }
  }
  private static func includes(_ url: URL, rule: WatchedFolderRule) -> Bool {
    guard rule == .screenshots else { return true }
    let name = url.deletingPathExtension().lastPathComponent.lowercased()
    let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff"]
    return imageExtensions.contains(url.pathExtension.lowercased())
      && (name.contains("screenshot") || name.contains("screen shot") || name.contains("screen capture"))
  }
  static func ready(previous: [WatchedEntry], current: [WatchedEntry], known: Set<String>, now: Date) -> [WatchedEntry] {
    let old = Dictionary(uniqueKeysWithValues: previous.map { ($0.name, $0) })
    return current.filter { !known.contains($0.name) && old[$0.name] == $0 && now.timeIntervalSince($0.modified) >= 2 }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}

@MainActor final class WatchedFolders: ObservableObject {
  static let shared = WatchedFolders()
  @Published private(set) var folders: [WatchedFolder] = []
  @Published var message: String?
  private weak var store: ParcelStore?
  private var sources: [UUID: DispatchSourceFileSystemObject] = [:]
  private var tasks: [UUID: Task<Void, Never>] = [:]
  private var access: [UUID: URL] = [:]
  private let defaults: UserDefaults
  private var writable = true
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: "parcel.watchedFolders") {
      do { folders = try JSONDecoder().decode([WatchedFolder].self, from: data) }
      catch { writable = false; message = "Saved watched folders could not be read. They have not been overwritten." }
    }
  }
  func start(store: ParcelStore) {
    self.store = store
    for folder in folders where folder.enabled { attach(folder) }
  }
  func add(folder url: URL, parcelID: UUID, rule: WatchedFolderRule = .all) {
    guard url.standardizedFileURL != StoragePaths.root.standardizedFileURL,
      !FileTree.isInside(url, directory: StoragePaths.root) else {
      message = "Skippy's own cache cannot be watched. Choose an ordinary folder to avoid import loops."; return
    }
    guard writable, folders.count < 8, !folders.contains(where: { $0.path == url.path }) else {
      message = "Choose a different folder. Up to eight watched folders are supported."; return
    }
    let scoped = url.startAccessingSecurityScopedResource()
    Task {
      do {
        let existing = try await Task.detached(priority: .utility) { try WatchedFolderScan.entries(at: url, rule: rule) }.value
        let folder = WatchedFolder(path: url.path,
          bookmark: try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil),
          parcelID: parcelID, knownNames: Set(existing.map(\.name)), rule: rule)
        if scoped { url.stopAccessingSecurityScopedResource() }
        folders.append(folder); persist(); attach(folder)
        message = "Watching new top-level files. Existing files were not imported."
      } catch {
        if scoped { url.stopAccessingSecurityScopedResource() }
        message = "Could not watch this folder: \(error.localizedDescription)"
      }
    }
  }
  func setEnabled(_ id: UUID, enabled: Bool) {
    guard writable, let index = folders.firstIndex(where: { $0.id == id }) else { return }
    detach(id); folders[index].enabled = enabled; persist()
    if enabled { attach(folders[index]) }
  }
  func remove(_ id: UUID) {
    guard writable else { return }
    detach(id); folders.removeAll { $0.id == id }; persist()
  }
  private func persist() {
    guard writable else { return }
    do { defaults.set(try JSONEncoder().encode(folders), forKey: "parcel.watchedFolders") }
    catch { message = error.localizedDescription }
  }
  private func detach(_ id: UUID) {
    sources.removeValue(forKey: id)?.cancel()
    tasks.removeValue(forKey: id)?.cancel()
    access.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
  }
  private func attach(_ folder: WatchedFolder) {
    guard sources[folder.id] == nil else { return }
    var stale = false
    let url = folder.bookmark.flatMap {
      try? URL(resolvingBookmarkData: $0, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
    } ?? URL(fileURLWithPath: folder.path)
    if url.startAccessingSecurityScopedResource() { access[folder.id] = url }
    let descriptor = open(url.path, O_EVTONLY)
    guard descriptor >= 0 else {
      access.removeValue(forKey: folder.id)?.stopAccessingSecurityScopedResource()
      message = "Watched folder unavailable: \(url.lastPathComponent)"; return
    }
    let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
      eventMask: [.write, .rename, .delete, .extend], queue: .main)
    source.setCancelHandler { close(descriptor) }
    source.setEventHandler { [weak self] in
      Task { @MainActor in self?.scan(folder.id, url: url) }
    }
    sources[folder.id] = source; source.resume(); scan(folder.id, url: url)
  }
  private func scan(_ id: UUID, url: URL) {
    tasks[id]?.cancel()
    tasks[id] = Task { [weak self] in
      guard let self else { return }
      var previous: [WatchedEntry] = []
      while !Task.isCancelled {
        do {
          let rule = folders.first(where: { $0.id == id })?.rule ?? .all
          let current = try await Task.detached(priority: .utility) { try WatchedFolderScan.entries(at: url, rule: rule) }.value
          guard !Task.isCancelled, let index = folders.firstIndex(where: { $0.id == id && $0.enabled }) else { return }
          let known = folders[index].knownNames.intersection(Set(current.map(\.name)))
          if known != folders[index].knownNames { folders[index].knownNames = known; persist() }
          let candidates = current.filter { !known.contains($0.name) }
          guard !candidates.isEmpty else { return }
          guard let store, store.boxes.contains(where: { $0.id == self.folders[index].parcelID }) else {
            message = "A watched folder's destination is in Bin or missing. Restore it or choose a new watch."; return
          }
          let stable = WatchedFolderScan.ready(previous: previous, current: current, known: known, now: Date())
          let generated = Set((store.boxes + store.trashedBoxes.map(\.box)).flatMap { box in
            box.items.compactMap(\.preparedPath) + [box.lastArchivePath].compactMap { $0 }
          }.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path })
          let ignored = stable.filter { generated.contains(url.appendingPathComponent($0.name).resolvingSymlinksInPath().standardizedFileURL.path) }
          if !ignored.isEmpty { folders[index].knownNames.formUnion(ignored.map(\.name)); persist() }
          let ready = stable.filter { !generated.contains(url.appendingPathComponent($0.name).resolvingSymlinksInPath().standardizedFileURL.path) }
          if candidates.allSatisfy({ self.folders[index].knownNames.contains($0.name) }) { return }
          if !ready.isEmpty, !store.busy, store.phase != .receiving, !store.needsLibraryRecovery {
            let previousError = store.error
            store.error = nil
            store.ingest(ready.map { url.appendingPathComponent($0.name) }, into: folders[index].parcelID)
            let intakeError = store.error
            store.error = previousError
            let accepted = Set(store.boxes.first(where: { $0.id == self.folders[index].parcelID })?.items.map { $0.sourceURL.lastPathComponent } ?? [])
            folders[index].knownNames.formUnion(ready.map(\.name).filter { accepted.contains($0) })
            persist()
            if let intakeError { message = "Watched folder: \(intakeError)"; return }
            message = "New files added to the watched parcel."
            if ready.allSatisfy({ self.folders[index].knownNames.contains($0.name) }), candidates.count == ready.count { return }
          }
          previous = current
          try await Task.sleep(for: .seconds(1))
        } catch is CancellationError { return }
        catch { message = "Watched folder: \(error.localizedDescription)"; return }
      }
    }
  }
}

import XCTest
@testable import ParcelApp

final class WatchedFolderTests: XCTestCase {
  func testScreenshotWatchFiltersOrdinaryDesktopFiles() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for name in ["Screenshot 2026-10-20.png", "notes.png", "Screen Shot 2026-10-20.jpg", "Screenshot.txt"] {
      try Data("fixture".utf8).write(to: folder.appendingPathComponent(name))
    }
    XCTAssertEqual(
      try WatchedFolderScan.entries(at: folder, rule: .screenshots).map(\.name).sorted(),
      ["Screen Shot 2026-10-20.jpg", "Screenshot 2026-10-20.png"])
  }

  func testLegacyWatchDecodesWithAllFilesRule() throws {
    let parcel = UUID()
    let json = "{\"id\":\"\(UUID())\",\"path\":\"/tmp\",\"parcelID\":\"\(parcel)\",\"enabled\":true,\"knownNames\":[]}".data(using: .utf8)!
    XCTAssertEqual(try JSONDecoder().decode(WatchedFolder.self, from: json).rule, .all)
  }

  func testOnlyNewStableFilesAfterAQuietPeriodAreReady() {
    let now = Date()
    let stable = WatchedEntry(name: "new.txt", bytes: 12, modified: now.addingTimeInterval(-3), directory: false)
    let known = WatchedEntry(name: "existing.txt", bytes: 9, modified: now.addingTimeInterval(-3), directory: false)
    let writing = WatchedEntry(name: "writing.mov", bytes: 12, modified: now, directory: false)
    XCTAssertEqual(WatchedFolderScan.ready(previous: [stable, known, writing], current: [stable, known, writing],
      known: [known.name], now: now), [stable])
    var changed = stable; changed.bytes = 30
    XCTAssertTrue(WatchedFolderScan.ready(previous: [stable], current: [changed], known: [], now: now).isEmpty)
  }
  @MainActor func testNativeWatchImportsNewFilesButNotBaselineOrPartialDownloads() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let existing = folder.appendingPathComponent("existing.txt")
    try "Keep original".write(to: existing, atomically: true, encoding: .utf8)
    let name = "ParcelWatchTest-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ParcelStore(persist: false)
    let manager = WatchedFolders(defaults: defaults)
    manager.start(store: store)
    manager.add(folder: StoragePaths.root, parcelID: try XCTUnwrap(store.selectedBox))
    XCTAssertTrue(manager.folders.isEmpty)
    XCTAssertTrue(manager.message?.contains("cache cannot be watched") == true)
    manager.add(folder: folder, parcelID: try XCTUnwrap(store.selectedBox))
    for _ in 0..<40 {
      if manager.folders.count == 1 { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    let record = try XCTUnwrap(manager.folders.first)
    defer { manager.remove(record.id) }
    let partial = folder.appendingPathComponent("new.mov.crdownload")
    try "Partial".write(to: partial, atomically: true, encoding: .utf8)
    let incoming = folder.appendingPathComponent("new.txt")
    try "New file".write(to: incoming, atomically: true, encoding: .utf8)
    for _ in 0..<80 {
      if store.items.count == 1 { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTAssertEqual(store.items.map(\.displayName), ["new.txt"])
    let finished = folder.appendingPathComponent("finished.mov")
    try FileManager.default.moveItem(at: partial, to: finished)
    for _ in 0..<60 {
      if store.items.count == 2 { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTAssertEqual(Set(store.items.map(\.displayName)), ["new.txt", "finished.mov"])
    let ownExport = folder.appendingPathComponent("own-export.zip")
    store.boxes[0].lastArchivePath = ownExport.path
    try "Generated fixture".write(to: ownExport, atomically: true, encoding: .utf8)
    for _ in 0..<60 {
      if manager.folders.first?.knownNames.contains(ownExport.lastPathComponent) == true { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTAssertTrue(manager.folders.first?.knownNames.contains(ownExport.lastPathComponent) == true)
    XCTAssertEqual(store.items.count, 2)
    manager.remove(record.id)
    XCTAssertEqual(try String(contentsOf: existing), "Keep original")
    XCTAssertEqual(try String(contentsOf: finished), "Partial")
    let later = folder.appendingPathComponent("after-removal.txt")
    try "Not watched".write(to: later, atomically: true, encoding: .utf8)
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(store.items.count, 2)
  }
}

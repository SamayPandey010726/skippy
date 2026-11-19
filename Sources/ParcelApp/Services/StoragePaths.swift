import AppKit
import Foundation
import ParcelCore

enum StoragePaths {
  #if PARCEL_TESTING
  static let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "Parcel-native-fixtures-" + UUID().uuidString, isDirectory: true)
  #else
  static let root = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(
      "Parcel", isDirectory: true)
  #endif
  static let library = root.appendingPathComponent("parcels.json")
  static let prepared = root.appendingPathComponent("Prepared", isDirectory: true)
  static let exports = root.appendingPathComponent("Exports", isDirectory: true)
  static let received = root.appendingPathComponent("Received", isDirectory: true)
  static func createDirectories() throws {
    for url in [root, prepared, exports, received] {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
  }
  @discardableResult static func deleteOwned(_ url: URL) -> Bool {
    guard [prepared, exports, received].contains(where: { FileTree.isInside(url, directory: $0) }),
      url != prepared, url != exports, url != received
    else { return false }
    do {
      try FileManager.default.removeItem(at: url)
      return true
    } catch { return false }
  }
}

@MainActor final class SourceAccess {
  private var retained: [String: URL] = [:]
  deinit { for url in retained.values { url.stopAccessingSecurityScopedResource() } }
  func retain(_ url: URL) {
    guard retained[url.path] == nil else { return }
    if url.startAccessingSecurityScopedResource() { retained[url.path] = url }
  }
  func bookmark(_ url: URL) -> Data? {
    try? url.bookmarkData(
      options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
      includingResourceValuesForKeys: nil, relativeTo: nil)
  }
  func resolve(_ item: ParcelItem) -> URL {
    guard let data = item.bookmark else { return item.sourceURL }
    var stale = false
    if let url = try? URL(
      resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil,
      bookmarkDataIsStale: &stale)
    {
      retain(url)
      return url
    }
    return item.sourceURL
  }
  func reconcile(_ paths: Set<String>) {
    for (path, url) in retained where !paths.contains(path) {
      url.stopAccessingSecurityScopedResource()
      retained.removeValue(forKey: path)
    }
  }
}

enum CoordinatedFiles {
  static func read<T>(_ url: URL, body: (URL) throws -> T) throws -> T {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var result: Result<T, Error>?
    coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError)
    { actual in
      result = Result { try body(actual) }
    }
    if let coordinationError { throw coordinationError }
    guard let result else { throw ParcelError.missingSource(url.lastPathComponent) }
    return try result.get()
  }
}

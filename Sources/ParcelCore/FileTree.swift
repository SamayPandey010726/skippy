import Foundation

public enum FileTree {
  public static let clutter: Set<String> = [".DS_Store", "__MACOSX"]
  public static func attributes(_ url: URL) throws -> [FileAttributeKey: Any] {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw ParcelError.missingSource(url.lastPathComponent)
    }
    return try FileManager.default.attributesOfItem(atPath: url.path)
  }
  public static func inspect(_ url: URL) throws -> (folder: Bool, bytes: Int64) {
    let attrs = try attributes(url)
    guard let type = attrs[.type] as? FileAttributeType,
      type == .typeRegular || type == .typeDirectory
    else {
      throw ParcelError.unsupportedSource(url.lastPathComponent)
    }
    return (type == .typeDirectory, (attrs[.size] as? NSNumber)?.int64Value ?? 0)
  }
  public static func copy(
    _ source: URL, to destination: URL, cleanMetadata: Bool,
    token: CancellationToken, depth: Int = 0
  ) throws -> Int64 {
    try token.check()
    guard depth < 128 else {
      throw ParcelError.storageError("This folder is nested too deeply to package safely.")
    }
    let before = try attributes(source)
    #if os(macOS)
      if (try? source.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == true {
        throw ParcelError.unsupportedSource(source.lastPathComponent)
      }
    #endif
    guard let type = before[.type] as? FileAttributeType else {
      throw ParcelError.unsupportedSource(source.lastPathComponent)
    }
    if type == .typeDirectory {
      try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
      var used = Set<String>()
      var bytes: Int64 = 0
      let children = try FileManager.default.contentsOfDirectory(
        at: source, includingPropertiesForKeys: nil
      )
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      for child in children {
        if cleanMetadata && clutter.contains(child.lastPathComponent) { continue }
        let name = try NamePolicy.unique(child.lastPathComponent, used: &used)
        bytes += try copy(
          child, to: destination.appendingPathComponent(name), cleanMetadata: cleanMetadata,
          token: token, depth: depth + 1)
      }
      let after = try attributes(source)
      guard before[.modificationDate] as? Date == after[.modificationDate] as? Date else {
        throw ParcelError.sourceChanged(source.lastPathComponent)
      }
      return bytes
    }
    guard type == .typeRegular else {
      throw ParcelError.unsupportedSource(source.lastPathComponent)
    }
    guard !FileManager.default.fileExists(atPath: destination.path) else {
      throw ParcelError.existingDestination
    }
    guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
      throw ParcelError.storageError("Could not create an output file.")
    }
    let input = try FileHandle(forReadingFrom: source)
    let output = try FileHandle(forWritingTo: destination)
    defer {
      try? input.close()
      try? output.close()
    }
    var copied: Int64 = 0
    while true {
      try token.check()
      let data = try input.read(upToCount: 1_048_576) ?? Data()
      if data.isEmpty { break }
      try output.write(contentsOf: data)
      copied += Int64(data.count)
    }
    try output.synchronize()
    let after = try attributes(source)
    guard before[.size] as? NSNumber == after[.size] as? NSNumber,
      before[.modificationDate] as? Date == after[.modificationDate] as? Date,
      copied == (before[.size] as? NSNumber)?.int64Value
    else { throw ParcelError.sourceChanged(source.lastPathComponent) }
    if let permissions = before[.posixPermissions] {
      try FileManager.default.setAttributes(
        [.posixPermissions: permissions], ofItemAtPath: destination.path)
    }
    return copied
  }
  public static func relativeEntries(in root: URL) throws -> [String] {
    var results: [String] = []
    func walk(_ url: URL, prefix: String) throws {
      for child in try FileManager.default.contentsOfDirectory(
        at: url, includingPropertiesForKeys: nil
      ).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let path = prefix + child.lastPathComponent
        let info = try inspect(child)
        results.append(path + (info.folder ? "/" : ""))
        if info.folder { try walk(child, prefix: path + "/") }
      }
    }
    try walk(root, prefix: "")
    return results
  }
  public static func isInside(_ child: URL, directory: URL) -> Bool {
    let c = child.standardizedFileURL.resolvingSymlinksInPath().path
    let root = directory.standardizedFileURL.resolvingSymlinksInPath().path
    return c == root || c.hasPrefix(root + "/")
  }
}

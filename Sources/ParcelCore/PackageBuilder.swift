import Foundation
import ZIPFoundation

public enum PackageBuilder {
  public static func manifest(title: String, note: String, entries: [ManifestEntry], date: Date)
    -> String
  {
    let f = ISO8601DateFormatter()
    var lines = ["PARCEL · \(title)", "Packed \(f.string(from: date))", "", "Contents"]
    for (i, e) in entries.enumerated() {
      lines.append("\(i + 1). \(e.name)\(e.folder ? "/" : "") · \(e.bytes) bytes")
    }
    if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      lines += ["", "Note", note]
    }
    lines += ["", "Originals were preserved. This list describes the packaged copies.", ""]
    return lines.joined(separator: "\n")
  }
  public static func build(
    inputs: [PackageInput], title: String, note: String = "", destination: URL,
    options: PackagingOptions = PackagingOptions(), token: CancellationToken = CancellationToken(),
    copySource: @Sendable (URL, URL, Bool, CancellationToken) throws -> Int64 = {
      try FileTree.copy($0, to: $1, cleanMetadata: $2, token: $3)
    },
    progress: @escaping @Sendable (Double, String) -> Void = { _, _ in }
  ) throws -> PackageResult {
    guard !inputs.isEmpty else { throw ParcelError.emptyCollection }
    let fm = FileManager.default
    guard !fm.fileExists(atPath: destination.path) else { throw ParcelError.existingDestination }
    let selected = inputs.filter {
      !(options.cleanMacMetadata && FileTree.clutter.contains($0.url.lastPathComponent))
    }
    guard !selected.isEmpty else {
      throw ParcelError.storageError(
        "Only Mac metadata was selected. Add another file, or turn cleanup off.")
    }
    for input in selected {
      let info = try FileTree.inspect(input.url)
      if info.folder && FileTree.isInside(destination, directory: input.url) {
        throw ParcelError.storageError(
          "Choose an output location outside the folder being packaged.")
      }
    }
    let staging = fm.temporaryDirectory.appendingPathComponent(
      "Parcel-job-" + UUID().uuidString, isDirectory: true)
    let payload = staging.appendingPathComponent("Contents", isDirectory: true)
    try fm.createDirectory(at: payload, withIntermediateDirectories: true)
    let partial = destination.deletingLastPathComponent().appendingPathComponent(
      ".parcel-" + UUID().uuidString + ".partial")
    defer {
      try? fm.removeItem(at: staging)
      try? fm.removeItem(at: partial)
      token.track(nil)
    }
    var used = Set<String>()
    var entries: [ManifestEntry] = []
    if options.includeManifest { used.insert(NamePolicy.key("Parcel contents.txt")) }
    for (index, input) in selected.enumerated() {
      try token.check()
      let name = try NamePolicy.unique(input.desiredName, used: &used)
      progress(Double(index) / Double(selected.count) * 0.55, "Gathering \(name)")
      let folder = try FileTree.inspect(input.url).folder
      let bytes = try copySource(
        input.url, payload.appendingPathComponent(name), options.cleanMacMetadata, token)
      entries.append(ManifestEntry(name: name, bytes: bytes, folder: folder))
    }
    let text = manifest(title: title, note: note, entries: entries, date: Date())
    if options.includeManifest {
      try text.write(
        to: payload.appendingPathComponent("Parcel contents.txt"), atomically: true, encoding: .utf8
      )
    }
    let paths = try FileTree.relativeEntries(in: payload)
    switch options.format {
    case .zip:
      // A local temporary ZIP is fully closed and verified before the final name is published.
      do {
        let archive = try Archive(url: partial, accessMode: .create)
        for (index, path) in paths.enumerated() {
          try token.check()
          progress(0.55 + Double(index) / Double(max(paths.count, 1)) * 0.4, "Sealing \(path)")
          let p = Progress(totalUnitCount: 0)
          token.track(p)
          try archive.addEntry(
            with: path, relativeTo: payload,
            compressionMethod: options.strength == .light ? .none : .deflate, progress: p)
        }
      }
      try token.check()
      do {
        let archive = try Archive(url: partial, accessMode: .read)
        guard Array(archive).count == paths.count else {
          throw ParcelError.storageError("Archive verification failed. Please try again.")
        }
      }
    case .sevenZip, .rar:
      guard let tool = ExternalArchiver.toolPath(for: options.format) else {
        throw ParcelError.storageError(ExternalArchiver.missingToolMessage(for: options.format))
      }
      try ExternalArchiver.archive(
        tool: tool, format: options.format, strength: options.strength, payload: payload,
        destination: partial, token: token, progress: progress)
    }
    // moveItem refuses to overwrite a destination that appeared while the job was running.
    try fm.moveItem(at: partial, to: destination)
    let bytes =
      (try fm.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
    progress(1, "Your parcel is ready")
    return PackageResult(archive: destination, entries: entries, bytes: bytes, manifestText: text)
  }
}

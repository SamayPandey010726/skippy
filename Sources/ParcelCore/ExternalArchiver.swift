import Foundation

/// Packs with the 7-Zip or RAR command-line tools when they are installed on
/// the Mac. ZIP stays on the built-in packer.
public enum ExternalArchiver {
  public static func toolPath(for format: PackFormat) -> String? {
    let names: [String]
    switch format {
    case .sevenZip: names = ["7zz", "7z"]
    case .rar: names = ["rar"]
    case .zip: return nil
    }
    let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
    let dirs = (pathEnv + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
      .split(separator: ":").map(String.init)
    var seen = Set<String>()
    for dir in dirs where seen.insert(dir).inserted {
      for name in names {
        let full = (dir as NSString).appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: full) { return full }
      }
    }
    return nil
  }

  public static func missingToolMessage(for format: PackFormat) -> String {
    switch format {
    case .sevenZip:
      return
        "7-Zip isn't installed on this Mac. Install it with: brew install p7zip — then pack again."
    case .rar:
      return
        "The RAR tool isn't installed on this Mac. Install it with: brew install rar — then pack again."
    case .zip: return ""
    }
  }

  /// Archives the staged payload directory into `destination`. The tool runs
  /// quietly in the background; cancelling the pack stops it too.
  public static func archive(
    tool: String, format: PackFormat, strength: PackStrength,
    payload: URL, destination: URL, token: CancellationToken,
    progress: @escaping @Sendable (Double, String) -> Void
  ) throws {
    try token.check()
    progress(0.55, "Sealing \(format.label)")
    let fm = FileManager.default
    let items = try fm.contentsOfDirectory(atPath: payload.path)
    guard !items.isEmpty else { throw ParcelError.emptyCollection }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.currentDirectoryURL = payload
    switch format {
    case .sevenZip:
      let level = strength == .light ? "1" : strength == .heavy ? "9" : "5"
      process.arguments = ["a", "-t7z", "-mx=\(level)", "-mmt=on", "-y", destination.path] + items
    case .rar:
      let level = strength == .light ? "1" : strength == .heavy ? "5" : "3"
      process.arguments = ["a", "-m\(level)", "-y", destination.path] + items
    case .zip:
      throw ParcelError.storageError("Internal error: ZIP uses the built-in packer.")
    }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    do {
      while process.isRunning {
        try token.check()
        Thread.sleep(forTimeInterval: 0.15)
      }
    } catch {
      process.terminate()
      throw error
    }
    guard process.terminationStatus == 0 else {
      throw ParcelError.storageError("\(format.label) packing failed. Please try again.")
    }
    let size =
      (try? fm.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
    guard fm.fileExists(atPath: destination.path), size > 0 else {
      throw ParcelError.storageError(
        "\(format.label) packing produced no file. Please try again.")
    }
    progress(0.95, "Your parcel is ready")
  }
}

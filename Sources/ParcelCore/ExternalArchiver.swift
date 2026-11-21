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
      return "7-Zip isn't installed on this Mac."
    case .rar:
      return "The RAR tool isn't installed on this Mac."
    case .zip: return ""
    }
  }

  private static func brewPath() -> String? {
    for p in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
      if FileManager.default.isExecutableFile(atPath: p) { return p }
    }
    let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
    for dir in pathEnv.split(separator: ":") {
      let full = (String(dir) as NSString).appendingPathComponent("brew")
      if FileManager.default.isExecutableFile(atPath: full) { return full }
    }
    return nil
  }

  /// Runs `brew install` for the tool behind the format. Blocking — call off
  /// the main thread.
  public static func installTool(for format: PackFormat) throws {
    let package: String
    switch format {
    case .sevenZip: package = "p7zip"
    case .rar: package = "rar"
    case .zip: return
    }
    guard let brew = brewPath() else {
      throw ParcelError.storageError(
        "Homebrew isn't installed. Install it from brew.sh, then install \(format.label).")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: brew)
    process.arguments = ["install", package]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let out =
        String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      throw ParcelError.storageError(
        "Could not install \(format.label): \(out.suffix(300).trimmingCharacters(in: .whitespacesAndNewlines))"
      )
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
      process.arguments = ["a", "-t7z", "-mx=\(level)", "-mmt=on", "-y", destination.path] + items.map { "./" + $0 }
    case .rar:
      let level = strength == .light ? "1" : strength == .heavy ? "5" : "3"
      process.arguments = ["a", "-m\(level)", "-y", destination.path] + items.map { "./" + $0 }
    case .zip:
      throw ParcelError.storageError("Internal error: ZIP uses the built-in packer.")
    }
    try run(process, format: format, failure: "Packing failed", token: token)
    let size = (try? fm.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
    guard fm.fileExists(atPath: destination.path), size > 0 else {
      throw ParcelError.storageError("\(format.label) packing produced no file.")
    }
    let verify = Process()
    verify.executableURL = URL(fileURLWithPath: tool)
    verify.arguments = ["t", format == .rar ? "-p-" : "-y", destination.path]
    try run(verify, format: format, failure: "Archive verification failed", token: token)
    progress(0.95, "Your parcel is ready")
  }

  private static func run(_ process: Process, format: PackFormat, failure: String, token: CancellationToken) throws {
    try token.check()
    process.standardInput = FileHandle.nullDevice
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
    try token.check()
    guard process.terminationStatus == 0 else {
      throw ParcelError.storageError(failure + " (" + format.label + ").")
    }
  }
}

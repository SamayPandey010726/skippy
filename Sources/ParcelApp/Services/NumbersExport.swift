import AppKit
import ParcelCore
import ZIPFoundation

enum NumbersExport {
  private static let identifier = "com.apple.iWork.Numbers"

  static func convert(_ source: URL, token: CancellationToken) async throws -> QuickConversionResult {
    guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) != nil else {
      throw ParcelError.storageError("Install Apple Numbers to export .numbers files to Excel.")
    }
    return try await Task.detached(priority: .userInitiated) { try exportCopy(source, token: token) }.value
  }

  private static func exportCopy(_ source: URL, token: CancellationToken) throws -> QuickConversionResult {
    try token.check()
    let fm = FileManager.default
    let root = StoragePaths.prepared.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let input = root.appendingPathComponent("Input.numbers")
    let name = NamePolicy.safeArchiveStem(source.deletingPathExtension().lastPathComponent)
    let output = root.appendingPathComponent(name + ".xlsx")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    do {
      try FileTree.copy(source, to: input, cleanMetadata: false, token: token)
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      process.arguments = ["-e", """
        on run argv
          set inputFile to POSIX file (item 1 of argv)
          set outputFile to POSIX file (item 2 of argv)
          with timeout of 90 seconds
            tell application id "com.apple.iWork.Numbers"
              set workbook to open inputFile
              try
                export workbook to outputFile as Microsoft Excel
              on error failureMessage number failureNumber
                close workbook saving no
                error failureMessage number failureNumber
              end try
              close workbook saving no
            end tell
          end timeout
        end run
        """, input.path, output.path]
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      try process.run()
      while process.isRunning {
        if token.isCancelled { process.terminate(); process.waitUntilExit(); try token.check() }
        Thread.sleep(forTimeInterval: 0.10)
      }
      try token.check()
      guard process.terminationStatus == 0 else {
        throw ParcelError.storageError("Numbers could not export the workbook. Check Automation access and that the workbook opens without a password.")
      }
      let archive = try Archive(url: output, accessMode: .read)
      guard archive["[Content_Types].xml"] != nil, archive["xl/workbook.xml"] != nil else {
        throw ParcelError.storageError("Numbers did not produce a readable Excel workbook.")
      }
      try fm.removeItem(at: input)
      return .init(url: output, ownedRoot: root)
    } catch {
      _ = StoragePaths.deleteOwned(root)
      throw error
    }
  }
}

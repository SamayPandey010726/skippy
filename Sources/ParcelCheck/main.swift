import Foundation
import ParcelCore
import ZIPFoundation

// Small actual-engine integration probe. Never touches user-selected originals.
let args = CommandLine.arguments
guard args.count == 2 else {
  print("Usage: ParcelCheck <new-output-directory>")
  exit(2)
}
let root = URL(fileURLWithPath: args[1], isDirectory: true)
do {
  guard !FileManager.default.fileExists(atPath: root.path) else {
    throw ParcelError.existingDestination
  }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let source = root.appendingPathComponent("source", isDirectory: true)
  try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
  let a = source.appendingPathComponent("hello 🌿.txt")
  try "An ordinary ZIP, with untouched originals.\n".write(to: a, atomically: true, encoding: .utf8)
  let destination = root.appendingPathComponent("Parcel.zip")
  let r = try PackageBuilder.build(
    inputs: [.init(url: a, desiredName: a.lastPathComponent)], title: "Integration check",
    destination: destination)
  print(r.archive.path)
  print("Archive bytes: \(r.bytes)")
} catch {
  fputs(error.localizedDescription + "\n", stderr)
  exit(1)
}

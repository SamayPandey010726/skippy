import Foundation
import XCTest
import ZIPFoundation

@testable import ParcelCore

final class PackagingTests: XCTestCase {
  private var root: URL!
  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Parcel-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
  private func file(_ path: String, _ contents: String) throws -> URL {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
  }
  private func readEntry(_ name: String, archive: Archive) throws -> Data {
    let entry = try XCTUnwrap(archive[name])
    var data = Data()
    _ = try archive.extract(entry, consumer: { data.append($0) })
    return data
  }
  func testPackagePreservesOriginalsAndExtractsWithCorrectContents() throws {
    let a = try file("A/readme.txt", "hello from A")
    let b = try file("B/README.txt", "hello from B")
    let destination = root.appendingPathComponent("handoff.zip")
    // Manifest behaviour under test: opt in explicitly (product default is off).
    var manifestOptions = PackagingOptions()
    manifestOptions.includeManifest = true
    let result = try PackageBuilder.build(
      inputs: [.init(url: a, desiredName: "readme.txt"), .init(url: b, desiredName: "README.txt")],
      title: "Launch", destination: destination, options: manifestOptions)
    XCTAssertEqual(result.entries.map(\.name), ["readme.txt", "README (2).txt"])
    XCTAssertEqual(try String(contentsOf: a), "hello from A")
    XCTAssertEqual(try String(contentsOf: b), "hello from B")
    let zip = try Archive(url: destination, accessMode: .read)
    XCTAssertEqual(
      String(data: try readEntry("readme.txt", archive: zip), encoding: .utf8), "hello from A")
    XCTAssertEqual(
      String(data: try readEntry("README (2).txt", archive: zip), encoding: .utf8), "hello from B")
    let manifest = try readEntry("Parcel contents.txt", archive: zip)
    XCTAssertFalse(String(decoding: manifest, as: UTF8.self).contains(root.path))
    XCTAssertGreaterThan(result.bytes, 0)
  }
  func testCleanupOnlyRemovesExplicitMacClutter() throws {
    _ = try file("folder/.DS_Store", "metadata")
    _ = try file("folder/__MACOSX/sidecar", "resource fork")
    _ = try file("folder/.env", "KEEP THIS")
    _ = try file("folder/nested/a.txt", "nested")
    let dest = root.appendingPathComponent("result.zip")
    _ = try PackageBuilder.build(
      inputs: [.init(url: root.appendingPathComponent("folder"), desiredName: "folder")],
      title: "Folder", destination: dest)
    let zip = try Archive(url: dest, accessMode: .read)
    XCTAssertNil(zip["folder/.DS_Store"])
    XCTAssertNil(zip["folder/__MACOSX/sidecar"])
    XCTAssertNotNil(zip["folder/.env"])
    XCTAssertNotNil(zip["folder/nested/a.txt"])
  }
  func testMetadataCleanupCanBeDisabled() throws {
    _ = try file("folder/.DS_Store", "keep")
    var options = PackagingOptions()
    options.cleanMacMetadata = false
    let dest = root.appendingPathComponent("result.zip")
    _ = try PackageBuilder.build(
      inputs: [.init(url: root.appendingPathComponent("folder"), desiredName: "folder")],
      title: "Test", destination: dest, options: options)
    XCTAssertNotNil(try Archive(url: dest, accessMode: .read)["folder/.DS_Store"])
  }
  func testManifestNameCollisionDoesNotClobberInput() throws {
    let a = try file("Parcel contents.txt", "my real document")
    let dest = root.appendingPathComponent("result.zip")
    // Manifest behaviour under test: opt in explicitly (product default is off).
    var manifestOptions = PackagingOptions()
    manifestOptions.includeManifest = true
    let r = try PackageBuilder.build(
      inputs: [.init(url: a, desiredName: a.lastPathComponent)], title: "Test", destination: dest,
      options: manifestOptions)
    XCTAssertEqual(r.entries.first?.name, "Parcel contents (2).txt")
    XCTAssertEqual(
      String(
        data: try readEntry(
          "Parcel contents (2).txt", archive: Archive(url: dest, accessMode: .read)),
        encoding: .utf8), "my real document")
  }
  func testDefaultBuildOmitsManifest() throws {
    // Product default: manifest off (Shreyash direction). A plain build
    // must not write "Parcel contents.txt", and an input with that name
    // keeps its name (no collision with a manifest entry).
    let a = try file("Parcel contents.txt", "my real document")
    let dest = root.appendingPathComponent("result.zip")
    let r = try PackageBuilder.build(
      inputs: [.init(url: a, desiredName: a.lastPathComponent)], title: "Test", destination: dest)
    XCTAssertEqual(r.entries.map(\.name), ["Parcel contents.txt"])
    let zip = try Archive(url: dest, accessMode: .read)
    XCTAssertEqual(
      String(
        data: try readEntry("Parcel contents.txt", archive: zip), encoding: .utf8),
      "my real document")
  }
  func testFailureDoesNotPublishOrLeavePartialArchive() throws {
    let a = try file("okay.txt", "okay")
    let dest = root.appendingPathComponent("result.zip")
    XCTAssertThrowsError(
      try PackageBuilder.build(
        inputs: [
          .init(url: a, desiredName: "okay.txt"),
          .init(url: root.appendingPathComponent("missing"), desiredName: "missing"),
        ], title: "Test", destination: dest))
    XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
    XCTAssertFalse(
      try FileManager.default.contentsOfDirectory(atPath: root.path).contains {
        $0.hasSuffix(".partial")
      })
  }
  func testDoesNotOverwriteDestination() throws {
    let a = try file("okay.txt", "okay")
    let dest = try file("result.zip", "untouched")
    XCTAssertThrowsError(
      try PackageBuilder.build(
        inputs: [.init(url: a, desiredName: "okay.txt")], title: "Test", destination: dest))
    XCTAssertEqual(try String(contentsOf: dest), "untouched")
  }
  func testCancellationDoesNotPublishOutput() throws {
    let a = try file("a.txt", String(repeating: "cancel", count: 4000))
    let dest = root.appendingPathComponent("result.zip")
    let token = CancellationToken()
    token.cancel()
    XCTAssertThrowsError(
      try PackageBuilder.build(
        inputs: [.init(url: a, desiredName: "a.txt")], title: "Test", destination: dest,
        token: token))
    XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
  }
  func testRejectsSymbolicLinksIncludingNestedLinks() throws {
    let a = try file("original.txt", "original")
    let folder = root.appendingPathComponent("folder")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: folder.appendingPathComponent("link"), withDestinationURL: a)
    let dest = root.appendingPathComponent("result.zip")
    XCTAssertThrowsError(
      try PackageBuilder.build(
        inputs: [.init(url: folder, desiredName: "folder")], title: "Test", destination: dest))
    XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
    XCTAssertEqual(try String(contentsOf: a), "original")
  }
  func testRejectsOutputInsideInputFolder() throws {
    _ = try file("folder/a.txt", "a")
    let folder = root.appendingPathComponent("folder")
    XCTAssertThrowsError(
      try PackageBuilder.build(
        inputs: [.init(url: folder, desiredName: "folder")], title: "Test",
        destination: folder.appendingPathComponent("recursive.zip")))
  }
  func testUnicodeNamesAndEmojiRoundTrip() throws {
    let a = try file("हेलो 🌿.txt", "नमस्ते")
    let dest = root.appendingPathComponent("result.zip")
    _ = try PackageBuilder.build(
      inputs: [.init(url: a, desiredName: a.lastPathComponent)], title: "Gift", destination: dest)
    let zip = try Archive(url: dest, accessMode: .read)
    XCTAssertEqual(
      String(data: try readEntry(a.lastPathComponent, archive: zip), encoding: .utf8), "नमस्ते")
  }
  func testEmptyFolderSurvives() throws {
    let folder = root.appendingPathComponent("empty")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let dest = root.appendingPathComponent("result.zip")
    _ = try PackageBuilder.build(
      inputs: [.init(url: folder, desiredName: "empty")], title: "Empty", destination: dest)
    XCTAssertNotNil(try Archive(url: dest, accessMode: .read)["empty/"])
  }
  func testTopLevelMacClutterIsExcludedWithoutDeletingOriginal() throws {
    let metadata = try file(".DS_Store", "metadata")
    let a = try file("document.txt", "keep")
    let dest = root.appendingPathComponent("result.zip")
    let r = try PackageBuilder.build(
      inputs: [
        .init(url: metadata, desiredName: ".DS_Store"), .init(url: a, desiredName: "document.txt"),
      ], title: "Test", destination: dest)
    XCTAssertEqual(r.entries.map(\.name), ["document.txt"])
    XCTAssertNil(try Archive(url: dest, accessMode: .read)[".DS_Store"])
    XCTAssertEqual(try String(contentsOf: metadata), "metadata")
  }
  func testCancellationAfterStagingDoesNotLeaveArchive() throws {
    let a = try file("a.txt", "keep")
    let dest = root.appendingPathComponent("result.zip")
    let token = CancellationToken()
    XCTAssertThrowsError(
      try PackageBuilder.build(
        inputs: [.init(url: a, desiredName: "a.txt")], title: "Test", destination: dest,
        token: token,
        copySource: { src, dst, clean, t in
          let copied = try FileTree.copy(src, to: dst, cleanMetadata: clean, token: t)
          t.cancel()
          return copied
        }))
    XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
    XCTAssertEqual(try String(contentsOf: a), "keep")
  }
  func testDestinationCreatedDuringJobIsNotOverwritten() throws {
    let a = try file("a.txt", "input")
    let dest = root.appendingPathComponent("result.zip")
    XCTAssertThrowsError(
      try PackageBuilder.build(
        inputs: [.init(url: a, desiredName: "a.txt")], title: "Test", destination: dest
      ) { fraction, _ in
        if fraction >= 0.55 && fraction < 1 {
          try? Data("unrelated existing file".utf8).write(to: dest)
        }
      })
    XCTAssertEqual(try String(contentsOf: dest), "unrelated existing file")
  }
}

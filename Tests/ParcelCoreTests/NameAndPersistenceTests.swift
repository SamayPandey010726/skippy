import XCTest

@testable import ParcelCore

final class NameAndPersistenceTests: XCTestCase {
  func testRejectsTraversalAndInvalidComponents() {
    for name in [
      "../secret", "..", ".", "", "/root", "a\\b", "a:b", "bad\u{0000}name",
      String(repeating: "a", count: 241),
    ] {
      XCTAssertThrowsError(try NamePolicy.validate(name), name)
    }
  }
  func testNamesUseCanonicalUnicodeAndCaseInsensitiveCollisionPolicy() throws {
    var used = Set<String>()
    XCTAssertEqual(try NamePolicy.unique("café.txt", used: &used), "café.txt")
    XCTAssertEqual(try NamePolicy.unique("CAFE\u{0301}.txt", used: &used), "CAFÉ (2).txt")
  }
  func testLongCollisionSuffixRemainsWithinLimit() throws {
    var used = Set<String>()
    let name = String(repeating: "界", count: 78) + ".txt"
    _ = try NamePolicy.unique(name, used: &used)
    XCTAssertLessThanOrEqual(try NamePolicy.unique(name, used: &used).utf8.count, 240)
  }
  func testDocumentRoundTripRetainsMissingReferencesAndPreparedState() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("library.json")
    var box = ParcelBox(name: "My research")
    var item = ParcelItem(
      sourcePath: "/not-currently-mounted/a.png", displayName: "a.png", byteCount: 120)
    item.preparedPath = "/generated/a.jpg"
    item.preparedBytes = 90
    box.items = [item]
    try CollectionStore.save(.init(boxes: [box], selectedBox: box.id), to: url)
    let doc = try CollectionStore.read(from: url)
    XCTAssertEqual(doc.boxes, [box])
    XCTAssertEqual(doc.selectedBox, box.id)
  }
  func testCorruptLibraryIsReportedNotSilentlyReplaced() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("not json".utf8).write(to: url)
    XCTAssertThrowsError(try CollectionStore.read(from: url))
    XCTAssertEqual(try String(contentsOf: url), "not json")
  }
}

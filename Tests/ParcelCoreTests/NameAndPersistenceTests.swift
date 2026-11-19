import XCTest

@testable import ParcelCore

final class NameAndPersistenceTests: XCTestCase {
  func testOldLibrariesLoadWithEmptyBinAndLegacyParcelPins() throws {
    var box = ParcelBox(name: "Old library")
    box.items = [ParcelItem(sourcePath: "/old", displayName: "old", isPinned: true)]
    let encoded = try JSONEncoder().encode(CollectionDocument(boxes: [box], selectedBox: box.id))
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    legacy.removeValue(forKey: "trashedBoxes")
    let document = try JSONDecoder().decode(CollectionDocument.self, from: JSONSerialization.data(withJSONObject: legacy))
    XCTAssertTrue(document.trashedBoxes.isEmpty)
    XCTAssertTrue(document.boxes[0].isShelfPinned)
  }
  func testBinRoundTripRetainsWholeParcelAndExactExpiry() throws {
    var box = ParcelBox(name: "Recoverable")
    box.isPinned = true
    box.note = "Keep this note"
    box.items = [ParcelItem(sourcePath: "/offline/file", displayName: "File")]
    let deleted = Date(timeIntervalSince1970: 1000)
    let entry = TrashedParcel(box: box, deletedAt: deleted)
    let document = CollectionDocument(boxes: [], selectedBox: nil, trashedBoxes: [entry])
    let restored = try JSONDecoder().decode(CollectionDocument.self, from: JSONEncoder().encode(document))
    XCTAssertEqual(restored.trashedBoxes, [entry])
    XCTAssertEqual(restored.trashedBoxes[0].expiresAt.timeIntervalSince(deleted), 30 * 86400)
  }

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
    item.inlineText = "OCR text"
    box.items = [item]
    try CollectionStore.save(.init(boxes: [box], selectedBox: box.id), to: url)
    let doc = try CollectionStore.read(from: url)
    XCTAssertEqual(doc.boxes, [box])
    XCTAssertEqual(doc.boxes[0].items[0].inlineText, "OCR text")
    XCTAssertEqual(doc.selectedBox, box.id)
  }
  func testStackIdentityAndCompactNameSurviveCoding() throws {
    var item = ParcelItem(sourcePath: "/offline/Quarterly_Revenue_Analysis.xlsx",
      displayName: "Quarterly_Revenue_Analysis.xlsx")
    item.stackID = UUID()
    let restored = try JSONDecoder().decode(ParcelItem.self, from: JSONEncoder().encode(item))
    XCTAssertEqual(restored.stackID, item.stackID)
    XCTAssertEqual(restored.compactDisplayName, "Quarterly Revenue…")
  }
  func testCorruptLibraryIsReportedNotSilentlyReplaced() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("not json".utf8).write(to: url)
    XCTAssertThrowsError(try CollectionStore.read(from: url))
    XCTAssertEqual(try String(contentsOf: url), "not json")
  }
}

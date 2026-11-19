import XCTest
@testable import ParcelApp
import ParcelCore

@MainActor final class SpotlightAndIntentTests: XCTestCase {
  func testSpotlightRecordsUsePrivateDeepLinksAndMetadataOnly() {
    var box = ParcelBox(name: "Launch assets")
    box.items = [
      ParcelItem(sourcePath: "/private/source/hero.png", displayName: "hero.png", byteCount: 20),
      ParcelItem(sourcePath: "/private/source/notes.txt", displayName: "notes.txt", byteCount: 10),
    ]
    let record = SpotlightParcelContent.records(for: [box]).first!
    XCTAssertEqual(record.identifier, box.id.uuidString)
    XCTAssertEqual(record.url.absoluteString, "parcel://open/\(box.id.uuidString)")
    XCTAssertTrue(record.description.contains("hero.png"))
    XCTAssertFalse(record.description.contains("/private/source"))
    XCTAssertTrue(record.keywords.contains("png"))
  }

  func testNamedAutomationCreationPinsExactlyOneParcel() {
    let store = ParcelStore(persist: false)
    let first = store.createNamedBox("First", pin: true)
    let second = store.createNamedBox("Second", pin: true)
    XCTAssertNotNil(first)
    XCTAssertEqual(store.boxes.filter(\.isShelfPinned).count, 1)
    XCTAssertEqual(store.boxes.first(where: { $0.id == second })?.name, "Second")
    XCTAssertNil(store.createNamedBox("   ", pin: true))
  }
}

import AppKit
import ParcelCore
import XCTest
@testable import ParcelApp

final class WorkspaceTests: XCTestCase {
  func testScientificCalculatorHasRightAssociativePowersAndRejectsInvalidFunctions() {
    var expression = NotchCalculator("-2^2 + 2^3^2 + sqrt(16) + cos(π)")
    XCTAssertEqual(expression.evaluate(), 511)
    var invalid = NotchCalculator("sqrt(-1)")
    XCTAssertNil(invalid.evaluate())
  }

  func testGridKeepsNativePixelDimensions() throws {
    func image(_ width: Int, _ height: Int) throws -> CGImage {
      let buffer = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      buffer.fill(CGRect(x: 0, y: 0, width: width, height: height))
      return try XCTUnwrap(buffer.makeImage())
    }
    let images = try [image(81, 40), image(59, 66), image(40, 27), image(87, 74)]
    let result = try XCTUnwrap(CaptureComposition.combine(images, columns: 2))
    XCTAssertEqual(result.width, 168)
    XCTAssertEqual(result.height, 140)
    XCTAssertEqual(CaptureComposition.pixelRect(CGRect(x: 5, y: 2, width: 9, height: 8),
      canvas: CGSize(width: 40.5, height: 20), image: images[0]), CGRect(x: 10, y: 4, width: 18, height: 16))
  }

  @MainActor func testQuickPinsPersistVisibilityAndSwapOverlappingSlots() throws {
    let name = "Skippy.Workspace." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = QuickPinStore(defaults: defaults)
    store.toggle(NotchModule.music.id)
    store.toggle(NotchModule.color.id)
    store.position(NotchModule.music.id, at: .upperLeft)
    store.setVisibility(NotchModule.music.id, always: true)
    let reopened = QuickPinStore(defaults: defaults)
    XCTAssertEqual(reopened.pins.map(\.position), [.upperLeft, .upperRight])
    XCTAssertTrue(reopened.isAlwaysVisible(reopened.pins[0]))
    XCTAssertFalse(reopened.isAlwaysVisible(reopened.pins[1]))
  }

  func testZIPRoundTripThroughShelfPreparation() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
    defer { try? FileManager.default.removeItem(at: url) }
    let bytes = Data("Archive fixture".utf8)
    try bytes.write(to: url)
    let token = CancellationToken()
    let zip = try ShelfArchivePipeline.compress([url], format: .zip, strength: .balanced, token: token) { _, _ in }
    defer { _ = StoragePaths.deleteOwned(zip.ownedRoot) }
    let restored = try ShelfArchivePipeline.extractZIP(zip.url, token: token)
    defer { _ = StoragePaths.deleteOwned(restored.ownedRoot) }
    XCTAssertEqual(try Data(contentsOf: restored.url.appendingPathComponent(url.lastPathComponent)), bytes)
  }

  func testEveryArrowHasADistinctDefaultGlobalShortcut() {
    let keys = WorkspaceShortcut.all.map { $0.defaultValue }
    let combinations = Set(keys.map { "\($0.keyCode):\($0.modifiers)" })
    XCTAssertEqual(combinations.count, keys.count)
    XCTAssertTrue(keys.allSatisfy(\.isValid))
  }
}

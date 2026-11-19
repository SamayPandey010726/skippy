import AppKit
import ParcelCore
import XCTest
@testable import ParcelApp

@MainActor final class DragConvertTests: XCTestCase {
  func testActionsAreContextualAndRequireOneSharedRoute() {
    let images = [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.jpg")]
    XCTAssertEqual(QuickConvertAction.available(for: images),
      [.jpeg, .png, .heic, .pdf, .searchableWord, .recognizedText])
    XCTAssertFalse(QuickConvertAction.available(for: [images[0]]).contains(.png))
    XCTAssertEqual(
      QuickConvertAction.available(for: [URL(fileURLWithPath: "/tmp/a.pdf")]),
      [.searchableWord, .recognizedText, .pngPages, .jpegPages])
    XCTAssertEqual(
      QuickConvertAction.available(for: [URL(fileURLWithPath: "/tmp/a.mov")]),
      [.compactVideo])
    XCTAssertEqual(QuickConvertAction.available(for: [URL(fileURLWithPath: "/tmp/a.docx")]), [.pdf])
    XCTAssertEqual(
      QuickConvertAction.available(for: [URL(fileURLWithPath: "/tmp/a.csv")]),
      [.excelWorkbook, .tsv, .spreadsheetPDF])
    XCTAssertEqual(
      QuickConvertAction.available(for: [URL(fileURLWithPath: "/tmp/a.xlsx")]),
      [.csv, .tsv, .spreadsheetPDF])
    XCTAssertTrue(QuickConvertAction.available(for: [images[0], URL(fileURLWithPath: "/tmp/a.mov")]).isEmpty)
  }

  func testEveryRibbonTargetHasAnExclusiveDropHitAndHeaderCancels() {
    let bounds = CGRect(x: 0, y: 0, width: 560, height: 108)
    for count in 1...6 {
      let geometry = DragConvertGeometry(count: count)
      for index in 0..<count {
        XCTAssertEqual(geometry.index(at: geometry.center(for: index, in: bounds), in: bounds), index)
        XCTAssertFalse(geometry.sectorPath(for: index, in: bounds).isEmpty)
      }
      XCTAssertNil(geometry.index(at: CGPoint(x: bounds.midX, y: bounds.maxY - 4), in: bounds))
      XCTAssertNil(geometry.index(at: CGPoint(x: bounds.minX, y: bounds.minY), in: bounds))
    }
  }

  func testBatchQuickConvertCreatesOneCopyPerInputInPrimaryParcel() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = try image(at: folder.appendingPathComponent("first.bmp"), color: .systemOrange)
    let second = try image(at: folder.appendingPathComponent("second.bmp"), color: .systemBlue)
    let store = ParcelStore(persist: false)
    let count = await withCheckedContinuation { continuation in
      store.quickConvert([first, second], action: .png) { count, error in
        XCTAssertNil(error)
        continuation.resume(returning: count)
      }
    }
    XCTAssertEqual(count, 2)
    XCTAssertEqual(store.items.count, 2)
    XCTAssertEqual(Set(store.items.map { $0.sourceURL.pathExtension }), ["png"])
    for item in store.items {
      XCTAssertTrue(FileManager.default.fileExists(atPath: item.sourcePath))
      XCTAssertNotEqual(item.sourceURL.deletingLastPathComponent().standardizedFileURL, folder.standardizedFileURL,
        "Converted copies belong to Parcel storage, never beside the source")
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    store.items.forEach { _ = StoragePaths.deleteOwned($0.sourceURL.deletingLastPathComponent()) }
  }

  private func image(at url: URL, color: NSColor) throws -> URL {
    let image = NSImage(size: CGSize(width: 80, height: 60))
    image.lockFocus(); color.setFill(); NSRect(x: 0, y: 0, width: 80, height: 60).fill(); image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let data = rep.representation(using: .bmp, properties: [:])
    else { throw XCTSkip("Could not create bitmap fixture") }
    try data.write(to: url)
    return url
  }
}

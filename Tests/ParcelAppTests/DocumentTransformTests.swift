import AppKit
import PDFKit
import ParcelCore
import XCTest
import ZIPFoundation
@testable import ParcelApp

@MainActor final class DocumentTransformTests: XCTestCase {
  private var fixtureFolder: URL!

  override func setUpWithError() throws {
    fixtureFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: fixtureFolder, withIntermediateDirectories: true)
    try StoragePaths.createDirectories()
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: fixtureFolder)
  }

  func testContextualTransformChoices() throws {
    let image = fixtureFolder.appendingPathComponent("scan.png")
    let pdf = fixtureFolder.appendingPathComponent("paper.pdf")
    XCTAssertEqual(
      DocumentTransformPipeline.available(for: [image]),
      [.searchableWord, .recognizedText, .imagesToPDF])
    XCTAssertEqual(
      DocumentTransformPipeline.available(for: [pdf]),
      [.searchableWord, .recognizedText, .pdfToPNG, .pdfToJPEG])
    XCTAssertEqual(
      DocumentTransformPipeline.available(for: [image, pdf]),
      [.searchableWord, .recognizedText])
  }

  func testWordAndSpreadsheetChoicesAreContextual() {
    XCTAssertEqual(DocumentTransformPipeline.available(for: [fixtureFolder.appendingPathComponent("report.docx")]), [.documentToPDF])
    XCTAssertEqual(DocumentTransformPipeline.available(for: [fixtureFolder.appendingPathComponent("table.csv")]),
      [.spreadsheetXLSX, .spreadsheetTSV, .spreadsheetPDF])
    XCTAssertEqual(DocumentTransformPipeline.available(for: [fixtureFolder.appendingPathComponent("table.xlsx")]),
      [.spreadsheetCSV, .spreadsheetTSV, .spreadsheetPDF])
  }

  func testSpreadsheetRoundTripAndDocumentPDF() async throws {
    let csv = fixtureFolder.appendingPathComponent("orders.csv")
    try "Order,Customer,Total\n1001,Samay,42.50\n1002,Parcel,18\n".write(to: csv, atomically: true, encoding: .utf8)
    let xlsx = try await DocumentTransformPipeline.transform(source: csv, kind: .spreadsheetXLSX, token: CancellationToken())
    defer { _ = StoragePaths.deleteOwned(xlsx.ownedRoot) }
    let archive = try Archive(url: xlsx.url, accessMode: .read)
    XCTAssertNotNil(archive["xl/workbook.xml"]); XCTAssertNotNil(archive["xl/worksheets/sheet1.xml"])
    let back = try await DocumentTransformPipeline.transform(source: xlsx.url, kind: .spreadsheetCSV, token: CancellationToken())
    defer { _ = StoragePaths.deleteOwned(back.ownedRoot) }
    let content = try String(contentsOf: back.url, encoding: .utf8)
    XCTAssertTrue(content.contains("1001,Samay,42.50"))
    let tablePDF = try await DocumentTransformPipeline.transform(source: csv, kind: .spreadsheetPDF, token: CancellationToken())
    defer { _ = StoragePaths.deleteOwned(tablePDF.ownedRoot) }
    XCTAssertEqual(PDFDocument(url: tablePDF.url)?.pageCount, 1)

    let text = fixtureFolder.appendingPathComponent("brief.txt")
    try "Parcel conversion quality check".write(to: text, atomically: true, encoding: .utf8)
    let documentPDF = try await DocumentTransformPipeline.transform(source: text, kind: .documentToPDF, token: CancellationToken())
    defer { _ = StoragePaths.deleteOwned(documentPDF.ownedRoot) }
    XCTAssertEqual(PDFDocument(url: documentPDF.url)?.pageCount, 1)
  }

  func testImageCreatesValidSearchableWordAndPDFCopies() async throws {
    let source = try makeImage(name: "Parcel OCR 4827")
    let original = try Data(contentsOf: source)
    let word = try await DocumentTransformPipeline.transform(
      source: source, kind: .searchableWord, token: CancellationToken(),
      recognizer: { _ in "Parcel OCR 4827" })
    defer { _ = StoragePaths.deleteOwned(word.ownedRoot) }
    let archive = try Archive(url: word.url, accessMode: .read)
    XCTAssertNotNil(archive["word/document.xml"])
    XCTAssertNotNil(archive["word/media/page1.png"])
    let xml = String(decoding: try read("word/document.xml", from: archive), as: UTF8.self)
    XCTAssertTrue(xml.contains("Recognized text"))
    XCTAssertTrue(xml.contains("Parcel OCR 4827"))
    XCTAssertTrue(xml.contains("rId1"))

    let pdf = try await DocumentTransformPipeline.transform(
      source: source, kind: .imagesToPDF, token: CancellationToken())
    defer { _ = StoragePaths.deleteOwned(pdf.ownedRoot) }
    XCTAssertEqual(PDFDocument(url: pdf.url)?.pageCount, 1)
    XCTAssertEqual(try Data(contentsOf: source), original)
  }

  func testNativeImageOCRReadsVisibleText() async throws {
    let source = try makeImage(name: "Parcel OCR 4827")
    let recognized = await TextRecognition.recognizeText(in: source)
    let text = try XCTUnwrap(recognized)
    XCTAssertTrue(text.localizedCaseInsensitiveContains("Parcel"))
    XCTAssertTrue(text.contains("4827"))
  }

  func testPDFRendersEveryPageAndCancelledJobLeavesNoOutput() async throws {
    let image = try makeImage(name: "Two pages")
    let pdfURL = fixtureFolder.appendingPathComponent("two.pdf")
    let document = PDFDocument()
    let sourceImage = try XCTUnwrap(NSImage(contentsOf: image))
    document.insert(try XCTUnwrap(PDFPage(image: sourceImage)), at: 0)
    document.insert(try XCTUnwrap(PDFPage(image: sourceImage)), at: 1)
    XCTAssertTrue(document.write(to: pdfURL))

    let result = try await DocumentTransformPipeline.transform(
      source: pdfURL, kind: .pdfToPNG, token: CancellationToken())
    defer { _ = StoragePaths.deleteOwned(result.ownedRoot) }
    let pages = try FileManager.default.contentsOfDirectory(at: result.url, includingPropertiesForKeys: nil)
    XCTAssertEqual(pages.map(\.lastPathComponent).sorted(), ["page-01.png", "page-02.png"])

    let cancelled = CancellationToken()
    cancelled.cancel()
    do {
      _ = try await DocumentTransformPipeline.transform(
        source: pdfURL, kind: .searchableWord, token: cancelled)
      XCTFail("A cancelled transform must not publish an output")
    } catch {
      XCTAssertEqual(error as? ParcelError, .cancelled)
    }
  }

  private func makeImage(name: String) throws -> URL {
    let image = NSImage(size: CGSize(width: 900, height: 420))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 900, height: 420).fill()
    NSColor.black.setFill()
    name.draw(
      at: CGPoint(x: 70, y: 170),
      withAttributes: [.font: NSFont.systemFont(ofSize: 72, weight: .semibold), .foregroundColor: NSColor.black])
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
    else { throw XCTSkip("Could not create image fixture") }
    let url = fixtureFolder.appendingPathComponent("fixture.png")
    try png.write(to: url)
    return url
  }

  private func read(_ path: String, from archive: Archive) throws -> Data {
    let entry = try XCTUnwrap(archive[path])
    var data = Data()
    _ = try archive.extract(entry) { data.append($0) }
    return data
  }
}

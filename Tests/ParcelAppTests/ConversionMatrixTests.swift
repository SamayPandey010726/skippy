import AppKit
import PDFKit
import ParcelCore
import XCTest
import ZIPFoundation
@testable import ParcelApp

@MainActor final class ConversionMatrixTests: XCTestCase {
  func testEverySupportedDocumentAndSpreadsheetRouteCreatesInspectableCopies() async throws {
    try StoragePaths.createDirectories()
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("build/Conversion-QA", isDirectory: true)
    try? FileManager.default.removeItem(at: root)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let token = CancellationToken()

    let image = root.appendingPathComponent("source-image.png")
    try makeImage().write(to: image)
    for action in [QuickConvertAction.jpeg, .png, .heic, .pdf] {
      let result = try await QuickConversionPipeline.convert(source: image, action: action, token: token)
      try publish(result.url, as: "image-to-\(action.rawValue).\(result.url.pathExtension)", in: root)
      _ = StoragePaths.deleteOwned(result.ownedRoot)
    }

    let word = try await DocumentTransformPipeline.transform(
      source: image, kind: .searchableWord, token: token, recognizer: { _ in "Parcel OCR quality check" })
    try publish(word.url, as: "image-ocr-to-word.docx", in: root)
    let wordPDF = try await DocumentTransformPipeline.transform(source: word.url, kind: .documentToPDF, token: token)
    try publish(wordPDF.url, as: "word-to-pdf.pdf", in: root)
    XCTAssertNotNil(PDFDocument(url: wordPDF.url))

    let sourcePDF = try await DocumentTransformPipeline.transform(source: image, kind: .imagesToPDF, token: token)
    for kind in [DocumentTransformKind.searchableWord, .recognizedText, .pdfToPNG, .pdfToJPEG] {
      let result = try await DocumentTransformPipeline.transform(
        source: sourcePDF.url, kind: kind, token: token, recognizer: { _ in "Parcel PDF OCR quality check" })
      try publish(result.url, as: "pdf-to-\(kind.rawValue)" + (result.url.hasDirectoryPath ? "" : ".\(result.url.pathExtension)"), in: root)
      _ = StoragePaths.deleteOwned(result.ownedRoot)
    }

    let csv = root.appendingPathComponent("source-spreadsheet.csv")
    try "Order,Customer,Total\n1001,Samay,42.50\n1002,Parcel,18\n".write(to: csv, atomically: true, encoding: .utf8)
    var workbook: URL?
    for kind in [DocumentTransformKind.spreadsheetXLSX, .spreadsheetTSV, .spreadsheetPDF] {
      let result = try await DocumentTransformPipeline.transform(source: csv, kind: kind, token: token)
      let copy = root.appendingPathComponent("csv-to-\(kind.rawValue).\(result.url.pathExtension)")
      try FileManager.default.copyItem(at: result.url, to: copy)
      if kind == .spreadsheetXLSX { workbook = copy }
      _ = StoragePaths.deleteOwned(result.ownedRoot)
    }
    let xlsx = try XCTUnwrap(workbook)
    for kind in [DocumentTransformKind.spreadsheetCSV, .spreadsheetTSV, .spreadsheetPDF] {
      let result = try await DocumentTransformPipeline.transform(source: xlsx, kind: kind, token: token)
      try publish(result.url, as: "xlsx-to-\(kind.rawValue).\(result.url.pathExtension)", in: root)
      _ = StoragePaths.deleteOwned(result.ownedRoot)
    }
    let ribbon = DragConvertView(frame: CGRect(x: 0, y: 0, width: 420, height: 108))
    ribbon.configure(urls: [xlsx], actions: [.csv, .tsv, .spreadsheetPDF], recent: .csv)
    let bitmap = try XCTUnwrap(ribbon.bitmapImageRepForCachingDisplay(in: ribbon.bounds))
    ribbon.cacheDisplay(in: ribbon.bounds, to: bitmap)
    let ribbonPNG = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try ribbonPNG.write(to: root.appendingPathComponent("conversion-ribbon.png"))

    _ = StoragePaths.deleteOwned(word.ownedRoot); _ = StoragePaths.deleteOwned(wordPDF.ownedRoot)
    _ = StoragePaths.deleteOwned(sourcePDF.ownedRoot)
    let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    XCTAssertGreaterThanOrEqual(files.count, 15)
  }

  private func makeImage() throws -> Data {
    let image = NSImage(size: CGSize(width: 640, height: 360)); image.lockFocus()
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 640, height: 360).fill()
    "Parcel conversion QA".draw(at: CGPoint(x: 70, y: 160), withAttributes: [.font: NSFont.systemFont(ofSize: 38, weight: .semibold)])
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { throw XCTSkip("Image fixture unavailable") }
    return png
  }

  private func publish(_ source: URL, as name: String, in root: URL) throws {
    let destination = root.appendingPathComponent(name, isDirectory: source.hasDirectoryPath)
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.copyItem(at: source, to: destination)
  }
}

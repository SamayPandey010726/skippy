import AppKit
import Foundation
import PDFKit
import ParcelCore
import ZIPFoundation

enum DocumentTransformKind: String, CaseIterable, Identifiable {
  case searchableWord
  case recognizedText
  case imagesToPDF
  case documentToPDF
  case pdfToPNG
  case pdfToJPEG
  case spreadsheetXLSX
  case spreadsheetCSV
  case spreadsheetTSV
  case spreadsheetPDF

  var id: String { rawValue }
  var label: String {
    switch self {
    case .searchableWord: return "Word (.docx)"
    case .recognizedText: return "Text (.txt)"
    case .imagesToPDF, .documentToPDF, .spreadsheetPDF: return "PDF (.pdf)"
    case .pdfToPNG: return "PNG pages"
    case .pdfToJPEG: return "JPG pages"
    case .spreadsheetXLSX: return "Excel (.xlsx)"
    case .spreadsheetCSV: return "CSV (.csv)"
    case .spreadsheetTSV: return "TSV (.tsv)"
    }
  }
  var icon: String {
    switch self {
    case .searchableWord: return "doc.text"
    case .recognizedText: return "text.viewfinder"
    case .imagesToPDF, .documentToPDF, .spreadsheetPDF: return "doc.richtext"
    case .pdfToPNG, .pdfToJPEG: return "photo.stack"
    case .spreadsheetXLSX: return "tablecells"
    case .spreadsheetCSV, .spreadsheetTSV: return "text.alignleft"
    }
  }
  var detail: String {
    switch self {
    case .searchableWord: return "Keeps each page visible and adds editable OCR text."
    case .recognizedText: return "Extracts readable text locally with Apple Vision."
    case .imagesToPDF: return "Combines selected images into one PDF per source."
    case .documentToPDF: return "Creates a PDF copy of a Word or text document."
    case .pdfToPNG: return "Renders every PDF page as a lossless image."
    case .pdfToJPEG: return "Renders every PDF page as a smaller JPEG image."
    case .spreadsheetXLSX: return "Creates a native Excel workbook copy."
    case .spreadsheetCSV: return "Creates a comma-separated table copy."
    case .spreadsheetTSV: return "Creates a tab-separated table copy."
    case .spreadsheetPDF: return "Creates a readable paginated table PDF."
    }
  }
}

struct DocumentTransformResult: Sendable {
  let url: URL
  let ownedRoot: URL
}

enum DocumentTransformPipeline {
  typealias Recognizer = (CGImage) async -> String?
  private struct Page {
    let png: Data
    let text: String
    let pixelSize: CGSize
  }

  static func canTransform(_ url: URL) -> Bool {
    isPDF(url) || isImage(url) || isDocument(url) || SpreadsheetTransformPipeline.canTransform(url)
  }

  static func available(for urls: [URL]) -> [DocumentTransformKind] {
    guard !urls.isEmpty else { return [] }
    var result: [DocumentTransformKind] = []
    if urls.allSatisfy({ isPDF($0) || isImage($0) }) {
      result += [.searchableWord, .recognizedText]
    }
    if urls.allSatisfy(isImage) { result.append(.imagesToPDF) }
    if urls.allSatisfy(isPDF) { result += [.pdfToPNG, .pdfToJPEG] }
    if urls.allSatisfy(isDocument) { result.append(.documentToPDF) }
    if urls.allSatisfy(SpreadsheetTransformPipeline.canTransform) {
      let source = urls[0].pathExtension.lowercased()
      if source != "xlsx" { result.append(.spreadsheetXLSX) }
      if source != "csv" { result.append(.spreadsheetCSV) }
      if source != "tsv" { result.append(.spreadsheetTSV) }
      result.append(.spreadsheetPDF)
    }
    return result
  }

  static func transform(
    source: URL, kind: DocumentTransformKind, token: CancellationToken,
    recognizer: Recognizer? = nil
  ) async throws -> DocumentTransformResult {
    try token.check()
    let root = StoragePaths.prepared.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    do {
      let stem = safeStem(source.deletingPathExtension().lastPathComponent)
      let output: URL
      switch kind {
      case .searchableWord:
        let pages = try await pagesWithOCR(source, token: token, recognizer: recognizer)
        output = root.appendingPathComponent(stem + " searchable.docx")
        try writeDOCX(pages: pages, to: output)
      case .recognizedText:
        let pages = try await pagesWithOCR(source, token: token, recognizer: recognizer)
        output = root.appendingPathComponent(stem + " OCR.txt")
        let text = pages.enumerated().map { index, page in
          pages.count > 1 ? "PAGE \(index + 1)\n\(page.text)" : page.text
        }.joined(separator: "\n\n")
        try text.write(to: output, atomically: true, encoding: .utf8)
      case .imagesToPDF:
        output = root.appendingPathComponent(stem + ".pdf")
        try writePDF(from: source, to: output)
      case .documentToPDF:
        output = root.appendingPathComponent(stem + ".pdf")
        try writeDocumentPDF(from: source, to: output)
      case .pdfToPNG, .pdfToJPEG:
        output = root.appendingPathComponent(stem + " pages", isDirectory: true)
        try renderPDF(source, to: output, jpeg: kind == .pdfToJPEG, token: token)
      case .spreadsheetXLSX, .spreadsheetCSV, .spreadsheetTSV, .spreadsheetPDF:
        let format: SpreadsheetTransformFormat
        switch kind {
        case .spreadsheetXLSX: format = .xlsx
        case .spreadsheetCSV: format = .csv
        case .spreadsheetTSV: format = .tsv
        case .spreadsheetPDF: format = .pdf
        default: fatalError("Mapped above")
        }
        output = try SpreadsheetTransformPipeline.transform(
          source: source, format: format, directory: root, token: token)
      }
      try token.check()
      return DocumentTransformResult(url: output, ownedRoot: root)
    } catch {
      _ = StoragePaths.deleteOwned(root)
      throw error
    }
  }

  private static func pagesWithOCR(
    _ source: URL, token: CancellationToken, recognizer: Recognizer?
  ) async throws -> [Page] {
    if isPDF(source) {
      guard let document = PDFDocument(url: source), document.pageCount > 0 else {
        throw ParcelError.storageError("\(source.lastPathComponent) is not a readable PDF.")
      }
      guard document.pageCount <= 500 else {
        throw ParcelError.storageError("PDF conversion supports up to 500 pages at a time.")
      }
      var result: [Page] = []
      for index in 0..<document.pageCount {
        try token.check()
        guard let page = document.page(at: index), let rendered = render(page: page) else {
          throw ParcelError.storageError("Page \(index + 1) could not be rendered.")
        }
        let text = await recognize(rendered.image, using: recognizer) ?? page.string ?? ""
        result.append(Page(png: rendered.png, text: text, pixelSize: rendered.size))
      }
      return result
    }
    guard let image = NSImage(contentsOf: source), let rendered = normalizedPNG(image) else {
      throw ParcelError.imageError("\(source.lastPathComponent) is not a readable image.")
    }
    try token.check()
    let text = await recognize(rendered.image, using: recognizer) ?? ""
    return [Page(png: rendered.png, text: text, pixelSize: rendered.size)]
  }

  private static func recognize(_ image: CGImage, using recognizer: Recognizer?) async -> String? {
    if let recognizer { return await recognizer(image) }
    return await TextRecognition.recognizeText(in: image)
  }

  private static func writePDF(from source: URL, to output: URL) throws {
    guard let image = NSImage(contentsOf: source), let page = PDFPage(image: image) else {
      throw ParcelError.imageError("\(source.lastPathComponent) could not be added to a PDF.")
    }
    let document = PDFDocument()
    document.insert(page, at: 0)
    guard document.write(to: output) else {
      throw ParcelError.storageError("The PDF copy could not be written.")
    }
  }

  private static func writeDocumentPDF(from source: URL, to output: URL) throws {
    let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
    let attributed: NSAttributedString
    do {
      attributed = try NSAttributedString(url: source, options: options, documentAttributes: nil)
    } catch {
      guard source.pathExtension.lowercased() == "docx",
        let text = try? docxText(source), !text.isEmpty
      else { throw ParcelError.storageError("\(source.lastPathComponent) is not a readable Word or text document.") }
      attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
    }
    let width: CGFloat = 540
    let storage = NSTextStorage(attributedString: attributed)
    let layout = NSLayoutManager()
    let container = NSTextContainer(containerSize: CGSize(width: width, height: .greatestFiniteMagnitude))
    container.widthTracksTextView = true
    layout.addTextContainer(container); storage.addLayoutManager(layout)
    layout.ensureLayout(for: container)
    let height = max(720, ceil(layout.usedRect(for: container).height) + 72)
    let view = NSTextView(frame: CGRect(x: 0, y: 0, width: width + 72, height: height), textContainer: container)
    view.textContainerInset = CGSize(width: 36, height: 36)
    view.drawsBackground = true; view.backgroundColor = .white
    let data = view.dataWithPDF(inside: view.bounds)
    try data.write(to: output, options: .atomic)
  }

  private static func docxText(_ source: URL) throws -> String {
    let archive = try Archive(url: source, accessMode: .read)
    guard let entry = archive["word/document.xml"] else { return "" }
    var data = Data(); _ = try archive.extract(entry) { data.append($0) }
    let xml = String(decoding: data, as: UTF8.self)
    return xml.replacingOccurrences(of: "</w:p>", with: "\n")
      .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
  }

  private static func renderPDF(_ source: URL, to folder: URL, jpeg: Bool, token: CancellationToken) throws {
    guard let document = PDFDocument(url: source), document.pageCount > 0 else {
      throw ParcelError.storageError("\(source.lastPathComponent) is not a readable PDF.")
    }
    guard document.pageCount <= 500 else {
      throw ParcelError.storageError("PDF conversion supports up to 500 pages at a time.")
    }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let digits = max(2, String(document.pageCount).count)
    for index in 0..<document.pageCount {
      try token.check()
      guard let page = document.page(at: index), let rendered = render(page: page),
        let bitmap = NSBitmapImageRep(data: rendered.png)
      else { throw ParcelError.storageError("Page \(index + 1) could not be rendered.") }
      let data = jpeg
        ? bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.86])
        : bitmap.representation(using: .png, properties: [:])
      guard let data else { throw ParcelError.storageError("Page \(index + 1) could not be encoded.") }
      let name = String(format: "page-%0*d.%@", digits, index + 1, jpeg ? "jpg" : "png")
      try data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }
  }

  private static func render(page: PDFPage) -> (image: CGImage, png: Data, size: CGSize)? {
    let bounds = page.bounds(for: .mediaBox)
    guard bounds.width > 0, bounds.height > 0 else { return nil }
    let scale = min(2.0, 1800 / max(bounds.width, bounds.height))
    let size = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    guard let context = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return nil }
    context.saveGState()
    context.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: context)
    context.restoreGState()
    image.unlockFocus()
    return normalizedPNG(image)
  }

  private static func normalizedPNG(_ image: NSImage) -> (image: CGImage, png: Data, size: CGSize)? {
    var rect = CGRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
    return (cgImage, png, CGSize(width: cgImage.width, height: cgImage.height))
  }

  private static func writeDOCX(pages: [Page], to output: URL) throws {
    guard !pages.isEmpty else { throw ParcelError.emptyCollection }
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Parcel-docx-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: staging) }
    let word = staging.appendingPathComponent("word", isDirectory: true)
    let media = word.appendingPathComponent("media", isDirectory: true)
    let relationships = word.appendingPathComponent("_rels", isDirectory: true)
    let rootRelationships = staging.appendingPathComponent("_rels", isDirectory: true)
    for folder in [staging, word, media, relationships, rootRelationships] {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    for (index, page) in pages.enumerated() {
      try page.png.write(to: media.appendingPathComponent("page\(index + 1).png"))
    }
    try contentTypes.write(to: staging.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
    try rootRels.write(to: rootRelationships.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
    try documentRelationships(count: pages.count).write(
      to: relationships.appendingPathComponent("document.xml.rels"), atomically: true, encoding: .utf8)
    try documentXML(pages: pages).write(
      to: word.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

    let archive = try Archive(url: output, accessMode: .create)
    let files = try relativeFiles(in: staging)
    for path in files {
      try archive.addEntry(with: path, relativeTo: staging, compressionMethod: .deflate)
    }
  }

  private static func documentXML(pages: [Page]) -> String {
    let body = pages.enumerated().map { index, page -> String in
      let maxWidth: Double = 5_760_000
      let ratio = page.pixelSize.height / max(page.pixelSize.width, 1)
      let height = Int(min(8_200_000, maxWidth * ratio))
      let picture = """
      <w:p><w:r><w:drawing><wp:inline><wp:extent cx="\(Int(maxWidth))" cy="\(height)"/><wp:docPr id="\(index + 1)" name="Page \(index + 1)"/><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="0" name="page\(index + 1).png"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="rId\(index + 1)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(Int(maxWidth))" cy="\(height)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
      """
      let heading = paragraph("Recognized text", bold: true)
      let recognized = page.text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { paragraph(String($0)) }.joined()
      let breakPage = index < pages.count - 1 ? "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>" : ""
      return picture + heading + recognized + breakPage
    }.joined()
    return """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"><w:body>\(body)<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720"/></w:sectPr></w:body></w:document>
    """
  }

  private static func paragraph(_ text: String, bold: Bool = false) -> String {
    let properties = bold ? "<w:rPr><w:b/></w:rPr>" : ""
    return "<w:p><w:r>\(properties)<w:t xml:space=\"preserve\">\(escapeXML(text))</w:t></w:r></w:p>"
  }

  private static func documentRelationships(count: Int) -> String {
    let links = (0..<count).map {
      "<Relationship Id=\"rId\($0 + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/page\($0 + 1).png\"/>"
    }.joined()
    return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(links)</Relationships>"
  }

  private static let contentTypes = """
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>
  """
  private static let rootRels = """
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
  """

  private static func relativeFiles(in root: URL) throws -> [String] {
    guard let enumerator = FileManager.default.enumerator(
      at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
    else { return [] }
    let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
    return try enumerator.compactMap { value in
      guard let url = value as? URL,
        try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
      else { return nil }
      let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
      guard resolved.hasPrefix(resolvedRoot + "/") else { return nil }
      return String(resolved.dropFirst(resolvedRoot.count + 1))
    }.sorted()
  }

  private static func isPDF(_ url: URL) -> Bool { url.pathExtension.lowercased() == "pdf" }
  private static func isImage(_ url: URL) -> Bool {
    ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"]
      .contains(url.pathExtension.lowercased())
  }
  private static func isDocument(_ url: URL) -> Bool {
    ["doc", "docx", "rtf", "rtfd", "txt"].contains(url.pathExtension.lowercased())
  }
  private static func safeStem(_ value: String) -> String {
    let clean = value.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? "Converted" : String(clean.prefix(120))
  }
  private static func escapeXML(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }
}

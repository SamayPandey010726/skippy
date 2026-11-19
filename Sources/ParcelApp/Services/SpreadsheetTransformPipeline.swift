import AppKit
import Foundation
import PDFKit
import ParcelCore
import ZIPFoundation

enum SpreadsheetTransformFormat: String {
  case xlsx, csv, tsv, pdf
}

enum SpreadsheetTransformPipeline {
  static func canTransform(_ url: URL) -> Bool {
    ["xlsx", "csv", "tsv"].contains(url.pathExtension.lowercased())
  }

  static func transform(
    source: URL, format: SpreadsheetTransformFormat, directory: URL, token: CancellationToken
  ) throws -> URL {
    try token.check()
    let rows = try read(source)
    guard !rows.isEmpty else { throw ParcelError.storageError("The spreadsheet is empty.") }
    let stem = NamePolicy.safeArchiveStem(source.deletingPathExtension().lastPathComponent)
    let output = directory.appendingPathComponent(stem + "." + format.rawValue)
    switch format {
    case .xlsx: try writeXLSX(rows, to: output)
    case .csv: try delimited(rows, separator: ",").write(to: output, atomically: true, encoding: .utf8)
    case .tsv: try delimited(rows, separator: "\t").write(to: output, atomically: true, encoding: .utf8)
    case .pdf: try writePDF(rows, to: output)
    }
    try token.check()
    return output
  }

  private static func read(_ source: URL) throws -> [[String]] {
    switch source.pathExtension.lowercased() {
    case "xlsx": return try readXLSX(source)
    case "csv": return parseDelimited(try String(contentsOf: source, encoding: .utf8), separator: ",")
    case "tsv": return parseDelimited(try String(contentsOf: source, encoding: .utf8), separator: "\t")
    default: throw ParcelError.storageError("Unsupported spreadsheet format.")
    }
  }

  static func parseDelimited(_ text: String, separator: Character) -> [[String]] {
    var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
    let characters = Array(text); var index = 0
    while index < characters.count {
      let character = characters[index]
      if character == "\"" {
        if quoted, index + 1 < characters.count, characters[index + 1] == "\"" { field.append("\""); index += 1 }
        else { quoted.toggle() }
      } else if character == separator, !quoted { row.append(field); field = "" }
      else if (character == "\n" || character == "\r"), !quoted {
        if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" { index += 1 }
        row.append(field); rows.append(row); row = []; field = ""
      } else { field.append(character) }
      index += 1
    }
    if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
    return rows
  }

  private static func delimited(_ rows: [[String]], separator: Character) -> String {
    rows.map { row in row.map { value in
      let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
      return escaped.contains(separator) || escaped.contains("\n") || escaped.contains("\"") ? "\"\(escaped)\"" : escaped
    }.joined(separator: String(separator)) }.joined(separator: "\n") + "\n"
  }

  private static func readXLSX(_ source: URL) throws -> [[String]] {
    let archive = try Archive(url: source, accessMode: .read)
    let shared = try archive["xl/sharedStrings.xml"].map { try strings(from: read($0, archive: archive), item: "si") } ?? []
    guard let sheet = archive["xl/worksheets/sheet1.xml"] else {
      throw ParcelError.storageError("The Excel workbook has no readable first sheet.")
    }
    return XLSXSheetParser(shared: shared).parse(try read(sheet, archive: archive))
  }

  private static func read(_ entry: Entry, archive: Archive) throws -> Data {
    var data = Data(); _ = try archive.extract(entry) { data.append($0) }; return data
  }

  private static func strings(from data: Data, item: String) throws -> [String] {
    let parser = XMLStringListParser(item: item); return parser.parse(data)
  }

  private static func writeXLSX(_ rows: [[String]], to output: URL) throws {
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("Parcel-xlsx-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: staging) }
    let workbook = staging.appendingPathComponent("xl", isDirectory: true)
    let sheets = workbook.appendingPathComponent("worksheets", isDirectory: true)
    let rels = workbook.appendingPathComponent("_rels", isDirectory: true)
    let rootRels = staging.appendingPathComponent("_rels", isDirectory: true)
    for folder in [staging, workbook, sheets, rels, rootRels] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    let types = #"<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>"#
    let root = #"<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"#
    let book = #"<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>"#
    let bookRels = #"<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>"#
    try types.write(to: staging.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
    try root.write(to: rootRels.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
    try book.write(to: workbook.appendingPathComponent("workbook.xml"), atomically: true, encoding: .utf8)
    try bookRels.write(to: rels.appendingPathComponent("workbook.xml.rels"), atomically: true, encoding: .utf8)
    let body = rows.enumerated().map { rowIndex, row in
      let cells = row.enumerated().map { column, value in
        #"<c r="\#(columnName(column))\#(rowIndex + 1)" t="inlineStr"><is><t xml:space="preserve">\#(escape(value))</t></is></c>"#
      }.joined()
      return "<row r=\"\(rowIndex + 1)\">\(cells)</row>"
    }.joined()
    let sheet = #"<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\#(body)</sheetData></worksheet>"#
    try sheet.write(to: sheets.appendingPathComponent("sheet1.xml"), atomically: true, encoding: .utf8)
    let archive = try Archive(url: output, accessMode: .create)
    for path in ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels", "xl/worksheets/sheet1.xml"] {
      try archive.addEntry(with: path, relativeTo: staging, compressionMethod: .deflate)
    }
  }

  private static func writePDF(_ rows: [[String]], to output: URL) throws {
    let document = PDFDocument(); let pageSize = CGSize(width: 792, height: 612)
    let perPage = 24
    for start in stride(from: 0, to: rows.count, by: perPage) {
      let pageRows = Array(rows[start..<min(rows.count, start + perPage)])
      let image = NSImage(size: pageSize)
      image.lockFocus(); NSColor.white.setFill(); NSRect(origin: .zero, size: pageSize).fill()
      let columns = max(1, min(8, pageRows.map(\.count).max() ?? 1)); let width = (pageSize.width - 48) / CGFloat(columns)
      for (rowIndex, row) in pageRows.enumerated() {
        for column in 0..<columns {
          let rect = CGRect(x: 24 + CGFloat(column) * width, y: pageSize.height - 38 - CGFloat(rowIndex + 1) * 22, width: width, height: 22)
          NSColor.separatorColor.setStroke(); NSBezierPath(rect: rect).stroke()
          let value = column < row.count ? row[column] : ""
          value.draw(in: rect.insetBy(dx: 4, dy: 4), withAttributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.labelColor])
        }
      }
      image.unlockFocus(); guard let page = PDFPage(image: image) else { throw ParcelError.storageError("The spreadsheet PDF could not be rendered.") }
      document.insert(page, at: document.pageCount)
    }
    guard document.write(to: output) else { throw ParcelError.storageError("The spreadsheet PDF could not be written.") }
  }

  private static func columnName(_ index: Int) -> String {
    var value = index + 1, result = ""
    while value > 0 { value -= 1; result = String(UnicodeScalar(65 + value % 26)!) + result; value /= 26 }
    return result
  }
  private static func escape(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
  }
}

private final class XMLStringListParser: NSObject, XMLParserDelegate {
  private let item: String; private var inside = false; private var value = ""; private var result: [String] = []
  init(item: String) { self.item = item }
  func parse(_ data: Data) -> [String] { let parser = XMLParser(data: data); parser.delegate = self; parser.parse(); return result }
  func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) { if elementName == item { inside = true; value = "" } }
  func parser(_ parser: XMLParser, foundCharacters string: String) { if inside { value += string } }
  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) { if elementName == item { result.append(value); inside = false } }
}

private final class XLSXSheetParser: NSObject, XMLParserDelegate {
  private let shared: [String]; private var rows: [[String]] = []; private var row: [String] = []
  private var cellType = "", reference = "", value = "", inline = ""; private var collectingValue = false, collectingText = false
  init(shared: [String]) { self.shared = shared }
  func parse(_ data: Data) -> [[String]] { let parser = XMLParser(data: data); parser.delegate = self; parser.parse(); return rows }
  func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
    if elementName == "row" { row = [] }
    if elementName == "c" { cellType = attributes["t"] ?? ""; reference = attributes["r"] ?? ""; value = ""; inline = "" }
    if elementName == "v" { collectingValue = true }
    if elementName == "t" { collectingText = true }
  }
  func parser(_ parser: XMLParser, foundCharacters string: String) { if collectingValue { value += string }; if collectingText { inline += string } }
  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
    if elementName == "v" { collectingValue = false }; if elementName == "t" { collectingText = false }
    if elementName == "c" {
      let index = Self.column(reference); while row.count < index { row.append("") }
      row.append(cellType == "s" ? (Int(value).flatMap { shared.indices.contains($0) ? shared[$0] : nil } ?? "") : (cellType == "inlineStr" ? inline : value))
    }
    if elementName == "row" { rows.append(row) }
  }
  private static func column(_ reference: String) -> Int {
    reference.prefix { $0.isLetter }.reduce(0) { $0 * 26 + Int($1.asciiValue! - 64) } - 1
  }
}

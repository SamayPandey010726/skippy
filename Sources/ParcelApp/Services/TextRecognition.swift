import Foundation
import Vision

/// On-device text recognition for images in a parcel.
/// Dropover ships OCR as a built-in file action; Parcel matches it here —
/// pull the words out of any image and copy them straight to the clipboard.
enum TextRecognition {
  /// Recognized text for one image, or nil when the image holds no text.
  static func recognizeText(in url: URL) async -> String? {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    let handler = VNImageRequestHandler(url: url, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return nil
    }
    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }

  /// File extensions we treat as readable text for "Copy text content".
  static let textExtensions: Set<String> = [
    "txt", "md", "markdown", "csv", "tsv", "json", "xml", "html", "htm", "css",
    "js", "ts", "swift", "py", "rb", "sh", "yml", "yaml", "toml", "ini",
    "log", "rtf", "text", "strings",
  ]

  static func isProbablyText(url: URL) -> Bool {
    textExtensions.contains(url.pathExtension.lowercased())
  }
}

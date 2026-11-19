import Foundation
import ParcelCore

enum ParcelNameSuggester {
  static func suggest(for items: [ParcelItem], date: Date = Date(), calendar: Calendar = .current) -> String? {
    guard !items.isEmpty else { return nil }
    let stems = items.map { ($0.effectiveName as NSString).deletingPathExtension }
    if let shared = sharedPrefix(stems), shared.count >= 3, !genericPrefixes.contains(shared.lowercased()) {
      return String("\(shared) · \(items.count) \(items.count == 1 ? "file" : "files")".prefix(80))
    }
    let category = categoryName(items)
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MMM d"
    return "\(category) · \(formatter.string(from: date))"
  }

  private static let genericPrefixes: Set<String> = ["img", "image", "dsc", "screen shot", "screenshot", "file", "document"]

  private static func sharedPrefix(_ values: [String]) -> String? {
    guard var prefix = values.first?.trimmingCharacters(in: .whitespacesAndNewlines), values.count > 1 else { return nil }
    for value in values.dropFirst() {
      while !value.lowercased().hasPrefix(prefix.lowercased()), !prefix.isEmpty { prefix.removeLast() }
      if prefix.isEmpty { return nil }
    }
    let separators = CharacterSet.alphanumerics.inverted
    return prefix.trimmingCharacters(in: separators.union(.whitespacesAndNewlines))
  }

  private static func categoryName(_ items: [ParcelItem]) -> String {
    let extensions = Set(items.map { ($0.effectiveName as NSString).pathExtension.lowercased() })
    if extensions.isSubset(of: ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp"]) { return "Images" }
    if extensions.isSubset(of: ["mov", "mp4", "m4v", "avi", "mkv"]) { return "Videos" }
    if extensions.isSubset(of: ["xls", "xlsx", "csv", "numbers"]) { return "Spreadsheets" }
    if extensions.isSubset(of: ["pdf", "doc", "docx", "txt", "rtf", "pages"]) { return "Documents" }
    if items.allSatisfy(\.isDirectory) { return "Folders" }
    return "Collected files"
  }
}

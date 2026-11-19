import Foundation

public enum FileSearchType: String, CaseIterable, Sendable {
  case any, excel, numbers, spreadsheets, images, videos, audio, pdf, text, archives, folders
  public var label: String { rawValue == "pdf" ? "PDF" : rawValue.capitalized }
  public func matches(_ item: ParcelItem) -> Bool {
    if self == .any { return true }
    let extensionName = item.effectiveURL.pathExtension.lowercased()
    if self == .numbers { return extensionName == "numbers" }
    if self == .folders { return item.isDirectory && !["numbers", "pages", "key"].contains(extensionName) }
    if self == .spreadsheets && extensionName == "numbers" { return true }
    if item.isDirectory { return false }
    switch self {
    case .any, .folders: return true
    case .excel: return ["xls", "xlsx", "xlsm", "xlsb", "xlt", "xltx", "xltm"].contains(extensionName)
    case .numbers: return extensionName == "numbers"
    case .spreadsheets: return Self.excel.matches(item) || Self.numbers.matches(item) || ["csv", "tsv", "ods"].contains(extensionName)
    case .images: return ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "tif", "svg", "avif", "bmp", "raw", "dng"].contains(extensionName)
    case .videos: return ["mov", "mp4", "m4v", "avi", "mkv", "webm", "mpeg", "mpg"].contains(extensionName)
    case .audio: return ["mp3", "wav", "m4a", "aac", "aiff", "flac", "ogg"].contains(extensionName)
    case .pdf: return extensionName == "pdf"
    case .text: return ["txt", "md", "rtf", "doc", "docx", "pages", "log", "json", "xml"].contains(extensionName)
    case .archives: return ["zip", "7z", "rar", "tar", "gz", "bz2", "xz"].contains(extensionName)
    }
  }
}

public enum FileSearchSize: String, CaseIterable, Sendable {
  case any, under1MB, from1To10MB, over10MB, over100MB
  public var label: String {
    switch self {
    case .any: return "Any size"
    case .under1MB: return "Under 1 MB"
    case .from1To10MB: return "1–10 MB"
    case .over10MB: return "Over 10 MB"
    case .over100MB: return "Over 100 MB"
    }
  }
  public func matches(_ bytes: Int64) -> Bool {
    switch self {
    case .any: return true
    case .under1MB: return bytes < 1_000_000
    case .from1To10MB: return (1_000_000...10_000_000).contains(bytes)
    case .over10MB: return bytes > 10_000_000
    case .over100MB: return bytes > 100_000_000
    }
  }
}

public enum FileSearchAdded: String, CaseIterable, Sendable {
  case anytime, today, yesterday, lastWeek
  public var label: String {
    switch self {
    case .anytime: return "Any added date"
    case .today: return "Added today"
    case .yesterday: return "Added yesterday"
    case .lastWeek: return "Added in last 7 days"
    }
  }
}

public struct ParcelFileQuery {
  public private(set) var types: Set<FileSearchType> = []
  public private(set) var addedInterval: DateInterval?
  public private(set) var dateDescription: String?
  public private(set) var warning: String?
  private var terms: [String] = []
  private var minimum: Double?
  private var maximum: Double?
  private var minimumInclusive = false
  private var maximumInclusive = false
  private var typeFilter: FileSearchType
  private var sizeFilter: FileSearchSize
  private var addedFilter: FileSearchAdded
  private var calendar: Calendar
  private var now: Date

  public init(_ text: String, type: FileSearchType = .any, size: FileSearchSize = .any,
              added: FileSearchAdded = .anytime, now: Date = Date(), calendar: Calendar = .current) {
    typeFilter = type; sizeFilter = size; addedFilter = added; self.now = now; self.calendar = calendar
    var remaining = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    func extract(_ pattern: String, _ apply: ([String]) -> Void) {
      guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
      let matches = expression.matches(in: remaining, range: NSRange(remaining.startIndex..., in: remaining))
      for match in matches.reversed() {
        let captures = (0..<match.numberOfRanges).map { index -> String in
          guard let range = Range(match.range(at: index), in: remaining) else { return "" }
          return String(remaining[range])
        }
        apply(captures)
        if let range = Range(match.range, in: remaining) { remaining.replaceSubrange(range, with: " ") }
      }
    }
    extract("\"([^\"]+)\"") { terms.append($0[1]) }
    let aliases: [(FileSearchType, String)] = [
      (.excel, "excel|xlsx|xls|xlsm|xlsb"), (.numbers, "numbers?|numbers\\s+files"),
      (.spreadsheets, "spreadsheets?|csv|tsv|ods"), (.images, "images?|photos?|pictures?|png|jpe?g|heic"),
      (.videos, "videos?|movies?|mp4|mov"), (.audio, "audio|music|mp3|wav"),
      (.pdf, "pdfs?"), (.text, "text|documents?|txt|markdown|docx|pages"),
      (.archives, "archives?|zips?|7z|rar"), (.folders, "folders?|directories")
    ]
    for (category, alias) in aliases { extract("\\b(?:" + alias + ")\\b") { _ in types.insert(category) } }
    extract("\\b(under|below|less than|smaller than|over|above|larger than|at least|at most)\\s*(\\d+(?:\\.\\d+)?)\\s*(bytes?|kb|mb|gb)\\b") { captures in
      let multiplier: Double = captures[3] == "gb" ? 1_000_000_000 : (captures[3] == "mb" ? 1_000_000 : (captures[3] == "kb" ? 1_000 : 1))
      guard let number = Double(captures[2]), (number * multiplier).isFinite else { return }
      if ["over", "above", "larger than", "at least"].contains(captures[1]) {
        minimum = number * multiplier; minimumInclusive = captures[1] == "at least"
      } else { maximum = number * multiplier; maximumInclusive = captures[1] == "at most" }
    }
    func date(_ year: Int, _ month: Int, _ day: Int) {
      guard let value = calendar.date(from: DateComponents(year: year, month: month, day: day)),
        calendar.component(.year, from: value) == year, calendar.component(.month, from: value) == month,
        calendar.component(.day, from: value) == day else { warning = "That added date is not valid."; return }
      addedInterval = calendar.dateInterval(of: .day, for: value)
      let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
      formatter.dateFormat = "d MMM yyyy"
      dateDescription = "Added " + formatter.string(from: value)
    }
    extract("\\b(\\d{4})-(\\d{1,2})-(\\d{1,2})\\b") { captures in
      date(Int(captures[1])!, Int(captures[2])!, Int(captures[3])!)
    }
    extract("\\b(\\d{1,2})(?:st|nd|rd|th)\\b") { captures in
      date(calendar.component(.year, from: now), calendar.component(.month, from: now), Int(captures[1])!)
    }
    extract("\\b(?:on)\\s+(\\d{1,2})\\b") { captures in
      date(calendar.component(.year, from: now), calendar.component(.month, from: now), Int(captures[1])!)
    }
    extract("\\b(today|yesterday|last\\s+7\\s+days|last\\s+week)\\b") { captures in
      let day = calendar.startOfDay(for: now)
      let start = calendar.date(byAdding: .day, value: captures[1] == "today" ? 0 : (captures[1] == "yesterday" ? -1 : -6), to: day)!
      let end = calendar.date(byAdding: .day, value: captures[1] == "yesterday" ? 0 : 1, to: day)!
      addedInterval = DateInterval(start: start, end: end)
      dateDescription = "Added " + captures[1]
    }
    let ignored: Set<String> = ["all", "file", "files", "show", "me", "find", "search", "uploaded", "upload", "added", "imported", "received", "on", "from", "the", "or", "and", "with", "of"]
    terms += remaining.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init).filter { !ignored.contains($0) }
  }

  public func matches(_ item: ParcelItem) -> Bool {
    guard warning == nil, typeFilter.matches(item), sizeFilter.matches(item.effectiveBytes),
      types.isEmpty || types.contains(where: { $0.matches(item) }) else { return false }
    let name = (item.displayName + " " + item.effectiveName).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    guard terms.allSatisfy({ name.contains($0) }) else { return false }
    let bytes = Double(item.effectiveBytes)
    if let minimum, minimumInclusive ? bytes < minimum : bytes <= minimum { return false }
    if let maximum, maximumInclusive ? bytes > maximum : bytes >= maximum { return false }
    if let addedInterval, !(item.addedAt >= addedInterval.start && item.addedAt < addedInterval.end) { return false }
    if addedFilter != .anytime {
      let start = calendar.startOfDay(for: now)
      let first = calendar.date(byAdding: .day, value: addedFilter == .today ? 0 : (addedFilter == .yesterday ? -1 : -6), to: start)!
      let last = calendar.date(byAdding: .day, value: addedFilter == .yesterday ? 0 : 1, to: start)!
      if item.addedAt < first || item.addedAt >= last { return false }
    }
    return true
  }
}

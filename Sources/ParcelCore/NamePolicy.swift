import Foundation

public enum NamePolicy {
  public static func validate(_ name: String) throws -> String {
    let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
      .precomposedStringWithCanonicalMapping
    guard !n.isEmpty, n != ".", n != "..", n.utf8.count <= 240,
      n.rangeOfCharacter(from: .controlCharacters) == nil,
      !n.contains("/"), !n.contains("\\"), !n.contains(":")
    else { throw ParcelError.invalidName(name) }
    return n
  }
  public static func key(_ name: String) -> String {
    name.precomposedStringWithCanonicalMapping.folding(
      options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
  }
  public static func unique(_ requested: String, used: inout Set<String>) throws -> String {
    let name = try validate(requested)
    var candidate = name
    var counter = 2
    let ext = (name as NSString).pathExtension
    let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
    while used.contains(key(candidate)) {
      let suffix = " (\(counter))" + (ext.isEmpty ? "" : ".\(ext)")
      var shortened = stem
      while (shortened + suffix).utf8.count > 240 { shortened.removeLast() }
      candidate = shortened + suffix
      counter += 1
    }
    used.insert(key(candidate))
    return candidate
  }
  public static func safeArchiveStem(_ title: String, date: Date? = nil) -> String {
    let filtered = title.unicodeScalars.map { scalar -> String in
      CharacterSet.controlCharacters.contains(scalar) || "/\\:".unicodeScalars.contains(scalar)
        ? "-" : String(scalar)
    }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    var stem = filtered.isEmpty || filtered == "." || filtered == ".." ? "My parcel" : filtered
    while stem.utf8.count > 180 { stem.removeLast() }
    if let date {
      let f = DateFormatter()
      f.locale = Locale(identifier: "en_US_POSIX")
      f.dateFormat = "yyyy-MM-dd"
      stem += " — " + f.string(from: date)
    }
    return stem
  }
}

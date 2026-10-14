import Foundation

struct AppPreferences: Codable, Equatable {
  var cleanMetadata = true
  // Shreyash direction: basic ZIP stays, manifest emphasis removed.
  // Saved user choices are preserved (load() decodes stored values).
  var includeManifest = false
  var appendDate = false
  var playSounds = false
  var exportFolder: String?
  var launchAtLogin = false
  /// Self-cleaning shelf: automatically clear unpinned items older than 24h on launch.
  var autoClearStale = true
  static func load() -> AppPreferences {
    guard let data = UserDefaults.standard.data(forKey: "preferences"),
      let p = try? JSONDecoder().decode(Self.self, from: data)
    else { return Self() }
    return p
  }
  func save() {
    if let data = try? JSONEncoder().encode(self) {
      UserDefaults.standard.set(data, forKey: "preferences")
    }
  }
}

import Foundation
import ParcelCore

/// Named, re-usable pack recipes. Inspired by CleanShot's editable project
/// presets: save the full packaging setup once, re-apply it in one tap.
struct PackProfile: Codable, Equatable, Identifiable {
  var id: UUID = UUID()
  var name: String
  var cleanMacMetadata: Bool
  var includeManifest: Bool
  var appendDate: Bool
  var compressArchive: Bool
  var format: PackFormat
  var strength: PackStrength
  var saveToDesktop: Bool

  init(name: String, from options: PackagingOptions) {
    self.name = name
    self.cleanMacMetadata = options.cleanMacMetadata
    self.includeManifest = options.includeManifest
    self.appendDate = options.appendDate
    self.compressArchive = options.compressArchive
    self.format = options.format
    self.strength = options.strength
    self.saveToDesktop = options.saveToDesktop
  }

  func apply(to options: inout PackagingOptions) {
    options.cleanMacMetadata = cleanMacMetadata
    options.includeManifest = includeManifest
    options.appendDate = appendDate
    options.compressArchive = compressArchive
    options.format = format
    options.strength = strength
    options.saveToDesktop = saveToDesktop
  }
}

enum PackProfileStore {
  private static let key = "parcel-pack-profiles"

  static func load() -> [PackProfile] {
    guard let data = UserDefaults.standard.data(forKey: key),
      let profiles = try? JSONDecoder().decode([PackProfile].self, from: data)
    else { return [] }
    return profiles
  }

  static func save(_ profiles: [PackProfile]) {
    if let data = try? JSONEncoder().encode(profiles) {
      UserDefaults.standard.set(data, forKey: key)
    }
  }
}

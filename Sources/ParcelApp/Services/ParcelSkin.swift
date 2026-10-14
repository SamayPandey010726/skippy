import SwiftUI

/// Parcel skins. Per Shreyash's direction, every skin shares the same
/// geometry, hit targets, state machine and accessibility structure —
/// the skin changes palette and illustration, never behaviour.
///
/// - Kraft Courier: the core brand — cardboard/kraft, paper, metal clip.
/// - Night Messenger: dark, softly glowing.
/// - Moss Courier: hand-painted natural materials, earthy warmth.
enum ParcelSkin: String, Codable, CaseIterable, Identifiable {
  case kraft, night, moss
  var id: String { rawValue }
  var name: String {
    switch self {
    case .kraft: return "Kraft Courier"
    case .night: return "Night Messenger"
    case .moss: return "Moss Courier"
    }
  }
  var blurb: String {
    switch self {
    case .kraft: return "Cardboard, paper, and a little metal clip."
    case .night: return "Dark, softly glowing, quiet after hours."
    case .moss: return "Hand-painted natural materials, earthy warmth."
    }
  }
  /// The shelf palette for this skin.
  var palette: SkinPalette {
    switch self {
    case .kraft:
      return SkinPalette(
        paper: Color(red: 0.953, green: 0.949, blue: 0.918),
        cream: Color(red: 0.925, green: 0.929, blue: 0.897),
        canvas: Color(red: 0.996, green: 0.991, blue: 0.971),
        accent: Color(red: 0.25, green: 0.37, blue: 0.35),
        accentSoft: Color(red: 0.36, green: 0.48, blue: 0.43),
        text: Color(red: 0.16, green: 0.23, blue: 0.24),
        secondary: Color(red: 0.49, green: 0.52, blue: 0.43),
        line: Color(red: 0.87, green: 0.86, blue: 0.79))
    case .night:
      return SkinPalette(
        paper: Color(red: 0.10, green: 0.11, blue: 0.14),
        cream: Color(red: 0.15, green: 0.16, blue: 0.20),
        canvas: Color(red: 0.18, green: 0.19, blue: 0.24),
        accent: Color(red: 0.65, green: 0.80, blue: 0.72),
        accentSoft: Color(red: 0.50, green: 0.65, blue: 0.58),
        text: Color(red: 0.93, green: 0.94, blue: 0.92),
        secondary: Color(red: 0.62, green: 0.64, blue: 0.60),
        line: Color(red: 0.28, green: 0.29, blue: 0.34))
    case .moss:
      return SkinPalette(
        paper: Color(red: 0.92, green: 0.90, blue: 0.84),
        cream: Color(red: 0.87, green: 0.86, blue: 0.76),
        canvas: Color(red: 0.97, green: 0.96, blue: 0.91),
        accent: Color(red: 0.30, green: 0.42, blue: 0.28),
        accentSoft: Color(red: 0.42, green: 0.55, blue: 0.38),
        text: Color(red: 0.20, green: 0.26, blue: 0.20),
        secondary: Color(red: 0.48, green: 0.52, blue: 0.42),
        line: Color(red: 0.82, green: 0.82, blue: 0.72))
    }
  }
}

struct SkinPalette: Equatable {
  var paper: Color
  var cream: Color
  var canvas: Color
  var accent: Color
  var accentSoft: Color
  var text: Color
  var secondary: Color
  var line: Color
}

/// Shared skin store: the selected skin, persisted, observable by SwiftUI.
@MainActor
final class SkinStore: ObservableObject {
  static let shared = SkinStore()
  @Published var skin: ParcelSkin {
    didSet {
      UserDefaults.standard.set(skin.rawValue, forKey: "parcel-skin")
    }
  }
  private init() {
    let raw = UserDefaults.standard.string(forKey: "parcel-skin")
    skin = ParcelSkin(rawValue: raw ?? "") ?? .kraft
  }
}

import AppKit
import SwiftUI

enum Ink {
  private static var palette: SkinPalette {
    (ParcelSkin(rawValue: UserDefaults.standard.string(forKey: "parcel-skin") ?? "") ?? .kraft).palette
  }
  static var paper: Color { palette.paper }
  static var cream: Color { palette.cream }
  static var canvas: Color { palette.canvas }
  static var green: Color { palette.accent }
  static var moss: Color { palette.accentSoft }
  static var paleGreen: Color { palette.accent.opacity(0.12) }
  static var text: Color { palette.text }
  static var secondary: Color {
    NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? palette.text : palette.secondary
  }
  static var line: Color {
    NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? palette.secondary : palette.line
  }
  static let peach = Color(red: 0.89, green: 0.60, blue: 0.44)
  static let serif = "Avenir Next"
}
struct MossButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  var secondary = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 13, weight: .semibold)).padding(.horizontal, 17).padding(
      .vertical, 11
    )
    .foregroundStyle(secondary ? Ink.green : Ink.paper)
    .background(secondary ? Ink.paleGreen : Ink.green, in: RoundedRectangle(cornerRadius: 11))
    .overlay(
      RoundedRectangle(cornerRadius: 11).stroke(secondary ? Ink.line : Ink.green, lineWidth: 1)
    )
    .scaleEffect(configuration.isPressed ? 0.97 : 1)
    .opacity(isEnabled ? 1 : 0.45)
    .animation(Motion.pressSquish, value: configuration.isPressed)
  }
}
struct QuietButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(Ink.secondary)
      .padding(.horizontal, 10).padding(.vertical, 7)
      .background(
        configuration.isPressed ? Ink.paleGreen : Color.clear, in: RoundedRectangle(cornerRadius: 8)
      )
      // Press squish: responds on mouse-down, not mouse-up.
      .scaleEffect(configuration.isPressed ? 0.95 : 1)
      .opacity(isEnabled ? 1 : 0.45)
      .animation(Motion.pressSquish, value: configuration.isPressed)
  }
}
/// Press-aware row style: the whole row squishes slightly on press,
/// so it feels like a physical object being picked up.
struct RowPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .animation(Motion.pressSquish, value: configuration.isPressed)
  }
}
struct PaperCard<Content: View>: View {
  let content: Content
  init(@ViewBuilder content: () -> Content) { self.content = content() }
  var body: some View {
    content.padding(18).background(Ink.canvas, in: RoundedRectangle(cornerRadius: 17)).overlay(
      RoundedRectangle(cornerRadius: 17).stroke(Ink.line.opacity(0.7), lineWidth: 1))
  }
}
func byteString(_ bytes: Int64) -> String {
  ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
struct TinyLeaf: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    p.addCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY),
      control1: CGPoint(x: rect.minX - rect.width * 0.1, y: rect.minY),
      control2: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.12))
    p.addCurve(
      to: CGPoint(x: rect.minX, y: rect.maxY),
      control1: CGPoint(x: rect.maxX + rect.width * 0.1, y: rect.maxY),
      control2: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.1))
    return p
  }
}
struct BrandMark: View {
  var body: some View {
    HStack(spacing: 9) {
      Image(systemName: "bag.fill").font(.system(size: 19)).foregroundStyle(Ink.green)
      Text("Skippy").font(.custom(Ink.serif, size: 27)).tracking(-1).foregroundStyle(Ink.green)
    }
  }
}

import AppKit
import SwiftUI

enum Ink {
  static let paper = Color(red: 0.953, green: 0.949, blue: 0.918)
  static let cream = Color(red: 0.925, green: 0.929, blue: 0.897)
  static let canvas = Color(red: 0.996, green: 0.991, blue: 0.971)
  static let green = Color(red: 0.25, green: 0.37, blue: 0.35)
  static let moss = Color(red: 0.36, green: 0.48, blue: 0.43)
  static let paleGreen = Color(red: 0.87, green: 0.90, blue: 0.87)
  static let text = Color(red: 0.16, green: 0.23, blue: 0.24)
  static let secondary = Color(red: 0.49, green: 0.52, blue: 0.43)
  static let line = Color(red: 0.87, green: 0.86, blue: 0.79)
  static let peach = Color(red: 0.89, green: 0.60, blue: 0.44)
  static let serif = "Avenir Next"
}
struct MossButtonStyle: ButtonStyle {
  var secondary = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 13, weight: .semibold)).padding(.horizontal, 17).padding(
      .vertical, 11
    )
    .foregroundStyle(secondary ? Ink.green : .white)
    .background(secondary ? Ink.paleGreen : Ink.green, in: RoundedRectangle(cornerRadius: 11))
    .overlay(
      RoundedRectangle(cornerRadius: 11).stroke(secondary ? Ink.line : Ink.green, lineWidth: 1)
    )
    .scaleEffect(configuration.isPressed ? 0.97 : 1)
    .animation(Motion.pressSquish, value: configuration.isPressed)
  }
}
struct QuietButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(Ink.secondary)
      .padding(.horizontal, 10).padding(.vertical, 7)
      .background(
        configuration.isPressed ? Ink.paleGreen : Color.clear, in: RoundedRectangle(cornerRadius: 8)
      )
      // Press squish: responds on mouse-down, not mouse-up.
      .scaleEffect(configuration.isPressed ? 0.95 : 1)
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
      Image(systemName: "folder.fill").font(.system(size: 19)).foregroundStyle(Ink.green)
      Text("parcel").font(.custom(Ink.serif, size: 27)).tracking(-1).foregroundStyle(Ink.green)
    }
  }
}

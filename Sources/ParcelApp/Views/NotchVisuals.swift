import SwiftUI

/// Parcel's notch language: compact, tactile and shared by every tool.
enum NotchUI {
  static let outerRadius: CGFloat = 22
  static let cardRadius: CGFloat = 14
  static let controlSize: CGFloat = 28
  static let gap: CGFloat = 8
}

struct ParcelNotchShape: Shape {
  var attachedToMenuBar = true
  func path(in rect: CGRect) -> Path {
    let top: CGFloat = attachedToMenuBar ? 3 : NotchUI.outerRadius
    return UnevenRoundedRectangle(
      cornerRadii: .init(topLeading: top, bottomLeading: NotchUI.outerRadius,
        bottomTrailing: NotchUI.outerRadius, topTrailing: top), style: .continuous
    ).path(in: rect)
  }
}

struct NotchCard<Content: View>: View {
  var tint: Color? = nil
  @ViewBuilder var content: () -> Content
  var body: some View {
    content()
      .padding(11)
      .background((tint ?? .white).opacity(tint == nil ? 0.055 : 0.11),
        in: RoundedRectangle(cornerRadius: NotchUI.cardRadius, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: NotchUI.cardRadius, style: .continuous)
        .strokeBorder(Color.white.opacity(0.075), lineWidth: 0.75))
  }
}

struct NotchIconButton: View {
  let symbol: String
  var tint: Color = .primary
  var selected = false
  var help: String
  var action: () -> Void
  @State private var hovering = false
  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(selected ? tint : .secondary)
        .frame(width: NotchUI.controlSize, height: NotchUI.controlSize)
        .background(selected ? tint.opacity(0.18) : Color.white.opacity(hovering ? 0.10 : 0.045),
          in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .scaleEffect(hovering ? 1.07 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(help)
    .help(help)
    .onHover { hovering = $0 }
    .animation(Motion.hoverLift, value: hovering)
  }
}

struct NotchActionButton: View {
  let title: String
  let symbol: String
  var tint: Color
  var action: () -> Void
  @State private var hovering = false
  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: symbol).font(.system(size: 10, weight: .bold))
        Text(title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
      }
      .foregroundStyle(tint)
      .padding(.horizontal, 11).frame(height: 29)
      .background(tint.opacity(hovering ? 0.22 : 0.13), in: Capsule())
      .contentShape(Capsule())
      .scaleEffect(hovering ? 1.025 : 1)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .onHover { hovering = $0 }
    .animation(Motion.hoverLift, value: hovering)
  }
}

struct NotchSectionTitle: View {
  let title: String
  let symbol: String
  var trailing: String? = nil
  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: symbol).font(.system(size: 9, weight: .bold))
      Text(title.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.7)
      Spacer()
      if let trailing { Text(trailing).font(.system(size: 8.5, weight: .medium)).foregroundStyle(.secondary) }
    }.foregroundStyle(.secondary)
  }
}

struct NotchWidgetButtonStyle: ButtonStyle {
  var tint: Color
  @State private var hovering = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(tint.opacity(hovering ? 0.14 : 0.075),
        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color.white.opacity(hovering ? 0.14 : 0.065), lineWidth: 0.8))
      .scaleEffect(configuration.isPressed ? 0.975 : (hovering ? 1.012 : 1))
      .shadow(color: .black.opacity(hovering ? 0.16 : 0.06), radius: hovering ? 9 : 3, y: 3)
      .onHover { hovering = $0 }
      .animation(Motion.hoverLift, value: hovering)
      .animation(Motion.pressSquish, value: configuration.isPressed)
  }
}

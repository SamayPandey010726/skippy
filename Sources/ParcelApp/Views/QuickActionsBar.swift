import SwiftUI

/// One-tap actions for the current parcel: pack and share without dialogs.
/// Ease-of-access strip inspired by Dropzone's action grid, scoped to
/// Parcel's core flow (gather → prepare → pack → share).
struct QuickActionsBar: View {
  @EnvironmentObject private var store: ParcelStore
  var body: some View {
    HStack(spacing: 10) {
      Text("QUICK ACTIONS").font(.system(size: 9, weight: .semibold)).tracking(1.5)
        .foregroundStyle(Ink.secondary)
      Spacer()
      QuickActionButton(
        icon: "archivebox", label: "Pack",
        help: "Pack this parcel right now with your current settings"
      ) { store.seal() }
      .disabled(store.busy || store.items.isEmpty || !store.canExport)
      QuickActionButton(
        icon: "wifi", label: "AirDrop",
        help: "Send this parcel to a nearby device"
      ) { store.airDrop() }
      .disabled(store.busy || store.items.isEmpty)
      QuickActionButton(
        icon: "list.bullet", label: "Contents",
        help: "Copy the contents list to the clipboard"
      ) { store.copyManifest() }
      .disabled(store.busy || store.items.isEmpty)
    }.padding(.horizontal, 28).padding(.vertical, 10)
      .background(Ink.cream.opacity(0.55))
  }
}

private struct QuickActionButton: View {
  @Environment(\.isEnabled) private var isEnabled
  let icon: String
  let label: String
  let help: String
  let action: () -> Void
  @State private var hovering = false
  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: icon).font(.system(size: 12))
        Text(label).font(.system(size: 12, weight: .medium))
      }.padding(.horizontal, 12).padding(.vertical, 7)
        .background(
          hovering && isEnabled ? Ink.moss.opacity(0.14) : Ink.canvas,
          in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 9)
            .stroke(Ink.line.opacity(0.8), lineWidth: 1)
        )
        .foregroundStyle(isEnabled ? Ink.green : Ink.secondary.opacity(0.5))
        .animation(Motion.hoverLift, value: hovering)
    }.buttonStyle(.plain)
      .help(help)
      .onHover { hovering = $0 }
  }
}

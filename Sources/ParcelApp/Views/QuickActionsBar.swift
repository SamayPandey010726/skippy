import SwiftUI

/// One-tap actions for the current parcel: pack and share without dialogs.
/// Ease-of-access strip inspired by Dropzone's action grid, scoped to
/// Parcel's core flow (gather → prepare → pack → share).
struct QuickActionsBar: View {
  @EnvironmentObject private var store: ParcelStore
  @StateObject private var skins = SkinStore.shared
  @ObservedObject private var history = RecentActionStore.shared
  var body: some View {
    HStack(spacing: 10) {
      Text("QUICK ACTIONS").font(.system(size: 9, weight: .semibold)).tracking(1.5)
        .foregroundStyle(Ink.secondary)
      Spacer()
      QuickActionButton(
        icon: "archivebox", label: "Pack",
        help: "Pack this parcel right now with your current settings"
      ) { record("pack", "Pack", "archivebox"); store.seal() }
      .disabled(store.busy || store.items.isEmpty || !store.canExport)
      QuickActionButton(
        icon: "wifi", label: "AirDrop",
        help: "Send this parcel to a nearby device"
      ) { record("airdrop", "AirDrop", "wifi"); store.airDrop() }
      .disabled(store.busy || store.items.isEmpty)
      QuickActionButton(
        icon: "wand.and.stars", label: "Transform",
        help: "Convert PDFs and images locally, including searchable Word OCR"
      ) { record("transform", "Transform", "wand.and.stars"); store.showTransform = true }
      .disabled(store.busy || store.availableTransforms.isEmpty || !store.canExport)
      QuickActionButton(
        icon: "list.bullet", label: "Contents",
        help: "Copy the contents list to the clipboard"
      ) { record("contents", "Copy contents", "list.bullet"); store.copyManifest() }
      .disabled(store.busy || store.items.isEmpty)
      if !history.actions.isEmpty {
        Menu {
          ForEach(history.actions.prefix(5)) { action in
            Button { run(action) } label: { Label(action.title, systemImage: action.symbol) }
          }
        } label: {
          Label("Recent", systemImage: "clock.arrow.circlepath")
            .font(.system(size: 12, weight: .medium))
        }.menuStyle(.borderlessButton).fixedSize()
      }
    }.padding(.horizontal, 28).padding(.vertical, 10)
      .background(Ink.cream.opacity(0.55))
  }
  private func record(_ id: String, _ title: String, _ symbol: String) {
    history.record(id: id, title: title, symbol: symbol)
  }
  private func run(_ action: RecentParcelAction) {
    switch action.id {
    case "pack": store.seal()
    case "airdrop": store.airDrop()
    case "contents": store.copyManifest()
    case "smart-name": store.nameCurrentFromContents()
    case "prepare.images", "prepare.videos", "transform": store.showTransform = true
    default:
      if action.id.hasPrefix("convert.") { store.showTransform = true }
    }
    history.record(id: action.id, title: action.title, symbol: action.symbol)
  }
}

private struct QuickActionButton: View {
  @StateObject private var skins = SkinStore.shared
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

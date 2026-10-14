import AppKit
import ParcelCore
import SwiftUI
import UniformTypeIdentifiers

/// The Dock picker: when you drag a file over Parcel's Dock icon and hold
/// (Spring Loading), Parcel activates and this panel appears near the Dock.
/// It shows your parcels — most recent first — plus a New parcel row.
/// Hover a parcel to peek inside; drop the file on a row to add it there.
///
/// This is the Dock-native version of the shelf: the same put-down →
/// navigate → pick-up job, without opening the app window.
@MainActor final class DockPickerController: NSObject {
  static let shared = DockPickerController()
  private weak var store: ParcelStore?
  private var panel: NSPanel?

  func install(store: ParcelStore) { self.store = store }

  var isVisible: Bool { panel?.isVisible == true }

  func show() {
    guard let store else { return }
    if panel == nil {
      let host = NSHostingView(rootView: DockPickerView().environmentObject(store))
      host.translatesAutoresizingMaskIntoConstraints = false
      let p = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 300, height: 320),
        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
      p.contentView = host
      p.backgroundColor = .clear
      p.isOpaque = false
      p.hasShadow = false
      p.level = .floating
      p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      p.ignoresMouseEvents = false
      panel = p
    }
    // Position near the Dock: bottom-center of the main screen, just
    // above where the Dock sits.
    if let screen = NSScreen.main {
      let frame = screen.visibleFrame
      let w: CGFloat = 300
      let h: CGFloat = 340
      let x = frame.midX - w / 2
      let y = frame.minY + 16
      panel?.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }
    panel?.orderFrontRegardless()
  }

  func hide() {
    panel?.orderOut(nil)
  }
}

struct DockPickerView: View {
  @EnvironmentObject private var store: ParcelStore
  @StateObject private var skinStore = SkinStore.shared
  @State private var hoveredBox: UUID?
  @State private var appeared = false

  /// Pinned-first (parcels with pinned items), then most recent. Caps at 5.
  private var pickerBoxes: [ParcelBox] {
    let withPinned = store.boxes.filter { $0.items.contains(where: \.isPinned) }
    let rest = store.boxes.filter { !$0.items.contains(where: \.isPinned) }
    let ordered = withPinned + rest
    return Array(ordered.prefix(5))
  }

  var body: some View {
    let p = skinStore.skin.palette
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "bag.fill").font(.system(size: 14)).foregroundStyle(p.accent)
        Text("Drop into a parcel").font(.system(size: 13, weight: .semibold))
          .foregroundStyle(p.text)
        Spacer()
        Text("Esc to close").font(.system(size: 10)).foregroundStyle(p.secondary)
      }.padding(.horizontal, 16).padding(.vertical, 12)
      Divider().background(p.line.opacity(0.5))
      ForEach(pickerBoxes) { box in
        parcelRow(box, palette: p)
      }
      newParcelRow(palette: p)
    }
    .background(
      RoundedRectangle(cornerRadius: 18).fill(p.paper)
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 18)
        .stroke(
          LinearGradient(
            colors: [.white.opacity(0.3), .white.opacity(0)],
            startPoint: .top, endPoint: .bottom),
          lineWidth: 0.75)
    )
    .scaleEffect(appeared ? 1 : 0.92)
    .opacity(appeared ? 1 : 0)
    .animation(Motion.uiReveal, value: appeared)
    .onAppear { appeared = true }
  }

  private func parcelRow(_ box: ParcelBox, palette p: SkinPalette) -> some View {
    let hovered = hoveredBox == box.id
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: box.items.contains(where: \.isPinned) ? "pin.fill" : "folder")
          .font(.system(size: 13)).foregroundStyle(p.accent)
        VStack(alignment: .leading, spacing: 2) {
          Text(box.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
            .foregroundStyle(p.text)
          Text("\(box.items.count) piece\(box.items.count == 1 ? "" : "s")")
            .font(.system(size: 10)).foregroundStyle(p.secondary)
        }
        Spacer()
        Image(systemName: "chevron.right").font(.system(size: 10))
          .foregroundStyle(p.secondary)
      }
      .padding(.horizontal, 16).padding(.vertical, 11)
      // Contents flyout: expands inline on hover.
      if hovered && !box.items.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(box.items.prefix(8)) { item in
            HStack(spacing: 6) {
              Image(systemName: item.isDirectory ? "folder" : "doc")
                .font(.system(size: 9)).foregroundStyle(p.secondary)
              Text(item.displayName).font(.system(size: 10)).lineLimit(1)
                .foregroundStyle(p.secondary)
              Spacer()
              if item.isPinned {
                Image(systemName: "pin.fill").font(.system(size: 8))
                  .foregroundStyle(p.accent)
              }
            }
          }
          if box.items.count > 8 {
            Text("+\(box.items.count - 8) more").font(.system(size: 10))
              .foregroundStyle(p.secondary)
          }
        }
        .padding(.horizontal, 16).padding(.leading, 23).padding(.bottom, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .background(hovered ? p.accent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
    .contentShape(Rectangle())
    .onHover { hoveredBox = $0 ? box.id : nil }
    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
      handleDrop(providers, into: box.id)
    }
    .animation(Motion.playfulSettle, value: hovered)
  }

  private func newParcelRow(palette p: SkinPalette) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "plus.circle.fill").font(.system(size: 14)).foregroundStyle(p.accent)
      Text("New parcel").font(.system(size: 12, weight: .medium)).foregroundStyle(p.text)
      Spacer()
    }
    .padding(.horizontal, 16).padding(.vertical, 11)
    .background(p.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    .contentShape(Rectangle())
    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
      store.newBox()
      guard let newID = store.selectedBox else { return false }
      return handleDrop(providers, into: newID)
    }
  }

  private func handleDrop(_ providers: [NSItemProvider], into boxID: UUID) -> Bool {
    var accepted = false
    for provider in providers where provider.canLoadObject(ofClass: URL.self) {
      accepted = true
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        guard let url else { return }
        Task { @MainActor in
          store.ingest([url], into: boxID)
          store.selectBox(boxID)
          DockPickerController.shared.hide()
          AppController.shared.openWorkbench()
        }
      }
    }
    return accepted
  }
}

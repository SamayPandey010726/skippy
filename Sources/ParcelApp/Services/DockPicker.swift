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
      let p = ShelfPanel(
        contentRect: NSRect(x: 0, y: 0, width: 300, height: 320),
        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
      p.contentView = host
      p.backgroundColor = .clear
      p.isOpaque = false
      p.hasShadow = false
      p.level = .popUpMenu
      p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      p.ignoresMouseEvents = false
      panel = p
    }
    // Position near the Dock, adapting to the screen and Dock side:
    // bottom Dock -> bottom-center; left Dock -> bottom-left;
    // right Dock -> bottom-right. Height caps to the visible frame.
    if let screen = NSScreen.main {
      let frame = screen.visibleFrame
      let w: CGFloat = min(300, frame.width - 32)
      let h: CGFloat = min(490, frame.height - 48)
      var x = frame.midX - w / 2
      var y = frame.minY + 16
      // Dock side heuristic: if the visible frame is inset on the left
      // or right (Dock occupies that edge), hug the opposite side.
      if frame.minX > screen.frame.minX + 40 {
        x = frame.minX + 16
      } else if screen.frame.maxX - frame.maxX > 40 {
        x = frame.maxX - w - 16
      }
      // Top Dock (rare): anchor to the top instead.
      if screen.frame.maxY - frame.maxY > 40 {
        y = frame.maxY - h - 16
      }
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
    ShelfRanking.destinations(store.boxes, limit: 5)
  }

  var body: some View {
    let p = skinStore.skin.palette
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "bag.fill").font(.system(size: 14)).foregroundStyle(p.accent)
        Text("Drop into a parcel").font(.system(size: 13, weight: .semibold))
          .foregroundStyle(p.text)
        Spacer()
        Button { DockPickerController.shared.hide() } label: {
          Image(systemName: "xmark").font(.system(size: 10))
        }.buttonStyle(.plain).accessibilityLabel("Close Dock picker")
      }.padding(.horizontal, 16).padding(.vertical, 12)
      Divider().background(p.line.opacity(0.5))
      ScrollView {
        VStack(spacing: 0) {
          ForEach(pickerBoxes) { box in parcelRow(box, palette: p) }
          newParcelRow(palette: p)
        }
      }
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
        Image(systemName: box.isShelfPinned ? "pin.fill" : "folder")
          .font(.system(size: 13)).foregroundStyle(p.accent)
        VStack(alignment: .leading, spacing: 2) {
          Text(box.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
            .foregroundStyle(p.text)
            .accessibilityLabel("\(box.name), \(box.items.count) piece\(box.items.count == 1 ? "" : "s")")
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
    .overlay(dropSurface(into: box.id))
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
    .overlay(dropSurface(into: nil))
  }

  private func dropSurface(into boxID: UUID?) -> some View {
    FileDropSurface(enabled: !store.busy,
      receive: { _ in }, receiving: { _ in },
      hover: { hoveredBox = $0 ? boxID : nil }, failure: { _ in },
      beginDrop: {
        DropPopupController.shared.summon()
        guard let handler = DropPopupController.shared.beginDrop(into: boxID) else { return nil }
        DockPickerController.shared.hide()
        return handler
      })
  }
}

import AppKit
import ParcelCore
import SwiftUI

struct CourierFileLayouts<Tile: View>: View {
  var items: [ParcelItem]
  var style: CourierViewStyle
  @ViewBuilder var tile: (ParcelItem) -> Tile

  var body: some View {
    Group {
      switch style {
      case .grid, .dial:
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
          ForEach(items) { item in tile(item).id(item.id) }
        }
      case .list:
        LazyVStack(spacing: 6) { ForEach(items) { item in tile(item).id(item.id) } }
      }
    }
    .animation(Motion.layoutRelayout, value: style)
  }
}

struct CourierControlStyle: ButtonStyle {
  var size: CGFloat = CourierLayout.controlSize
  @State private var hovered = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: min(28, max(12, size * 0.375)), weight: .medium))
      .frame(minWidth: size, minHeight: size)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9))
      .background(.primary.opacity(configuration.isPressed ? 0.16 : (hovered ? 0.09 : 0)), in: RoundedRectangle(cornerRadius: 9))
      .contentShape(Rectangle())
      .scaleEffect(configuration.isPressed ? 0.94 : (hovered ? 1.12 : 1))
      .animation(Motion.pressSquish, value: configuration.isPressed)
      .animation(Motion.hoverLift, value: hovered)
      .onHover { hovered = $0 }
  }
}

struct CourierToolbar: View {
  @ObservedObject var shelf: DropPopupController
  var box: ParcelBox
  var skin: ParcelSkin
  var hoveredItem: ParcelItem?
  var delete: () -> Void
  @EnvironmentObject private var store: ParcelStore
  private var locked: Bool { store.busy || shelf.receiving || store.phase == .receiving }
  @State private var clipboardMagneticHovered = false
  @State private var deleteDropHovered = false
  var body: some View {
    VStack(spacing: 3) {
      HStack(spacing: 2) {
        HStack(spacing: 2) {
          Button(action: shelf.dismiss) { Image(systemName: "xmark") }.help("Close parcel")
          Button(action: shelf.toggleClipboard) { Image(systemName: "list.clipboard") }
            .scaleEffect(clipboardMagneticHovered ? 1.22 : 1)
            .animation(Motion.hoverLift, value: clipboardMagneticHovered)
            .help("Clipboard history")
            .overlay {
              FileDropSurface(enabled: !locked, tap: shelf.toggleClipboard, receive: { _ in }, receiving: { _ in },
                hover: { inside in clipboardMagneticHovered = inside; shelf.clipboardHoverChanged(inside) },
                failure: { _ in }, tracksPointer: true, acceptsDrops: false)
                .frame(width: 42, height: 42)
            }
          Button { shelf.showModule(.dashboard) } label: { Image(systemName: "square.grid.2x2") }
            .help("Open Parcels")
          if store.selectedItems.count > 1 {
            Button(action: store.stackSelected) { Image(systemName: "square.stack.3d.up.fill") }
              .help("Stack \(store.selectedItems.count) selected items into one icon")
          }
        }
        Spacer(minLength: 4)
        HStack(spacing: 2) {
          Button(action: shelf.toggleSearch) { Image(systemName: "magnifyingglass") }
            .help("Search and filter").onHover(perform: shelf.searchHoverChanged)
          Button(action: delete) { Image(systemName: "trash") }
            .scaleEffect(deleteDropHovered ? 1.22 : 1)
            .animation(Motion.hoverLift, value: deleteDropHovered)
            .help("Move parcel to Bin")
            .overlay {
              FileDropSurface(enabled: !locked, tap: delete, receive: { _ in },
                receiving: { _ in }, hover: { deleteDropHovered = $0 }, failure: { _ in },
                beginDrop: {
                  guard let hoveredItem else { return nil }
                  return shelf.beginItemDeleteDrop(hoveredItem.id, from: box.id)
                }, tracksPointer: true, dragHover: { deleteDropHovered = $0 })
                .frame(width: 42, height: 42)
                .accessibilityLabel("Delete dropped item or stack")
            }
          options
        }
      }
      .overlay {
        Text(box.name).font(.system(size: 11, weight: .semibold)).lineLimit(1).frame(maxWidth: 120)
          .contentShape(Rectangle()).overlay {
            FileDropSurface(enabled: !locked, tap: {}, receive: { _ in }, receiving: { _ in }, hover: { _ in },
              failure: { _ in }, doubleTap: { shelf.renameParcel(box.id) },
              archiveForDrag: { shelf.prepareArchive(for: box.id, $0) })
          }.help("Double-click to rename · drag to pack and send")
      }.frame(height: 26)
      if locked {
        HStack(spacing: 6) {
          ProgressView(value: shelf.receiving ? nil : store.progress).frame(maxWidth: .infinity)
          Text(store.progressLabel).font(.system(size: 10)).lineLimit(1)
          Button("Cancel", action: store.cancel).font(.system(size: 11))
        }
      }
      if shelf.statusVisible || shelf.failed {
        Text(shelf.message).font(.system(size: 10)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
          .foregroundStyle(shelf.failed ? .orange : skin.palette.secondary)
      }
    }.buttonStyle(CourierControlStyle(size: 24)).padding(3)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
  }

  private var options: some View {
    Button(action: { shelf.toggleOptions(delete: delete) }) { Image(systemName: "ellipsis.circle") }
      .help("Options").onHover { shelf.optionsHoverChanged($0, delete: delete) }
  }
}

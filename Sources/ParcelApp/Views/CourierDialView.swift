import AppKit
import ParcelCore
import SwiftUI

struct CourierDialView: View {
  @ObservedObject var shelf: DropPopupController
  var box: ParcelBox
  var skin: ParcelSkin
  var delete: () -> Void
  @EnvironmentObject private var store: ParcelStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.courierStaticRendering) private var staticRendering
  @State private var focus = 0
  @State private var wheel = CourierDialScroll()
  @State private var revealed = false
  @State private var hovered: UUID?
  @State private var dragging: UUID?
  private var preview: CourierHoverPreview { shelf.filePreview }
  private var items: [ParcelItem] { store.compactItems(store.filteredItems(in: box)) }
  private var locked: Bool { store.busy || shelf.receiving || store.phase == .receiving }
  private var palette: SkinPalette { skin.palette }
  init(shelf: DropPopupController, box: ParcelBox, skin: ParcelSkin, delete: @escaping () -> Void) {
    self.shelf = shelf; self.box = box; self.skin = skin; self.delete = delete
    _focus = State(initialValue: CourierFanLayout.initialIndex(count: box.items.count))
  }

  var body: some View {
    VStack(spacing: 8) {
      CourierToolbar(shelf: shelf, box: box, skin: skin,
        hoveredItem: (dragging ?? hovered).flatMap { id in items.first(where: { $0.id == id }) }, delete: delete)
      GeometryReader { geometry in
        let straight = shelf.parkedInMenuBar
        let compact = !straight && (geometry.size.width < 260 || (items.count > 3 && geometry.size.height < (shelf.side.isVertical ? 180 : 300)))
        let centerIndex = CourierFanLayout.wrappedIndex(focus, count: items.count)
        let slots = compact ? (items.isEmpty ? [] : [CourierFanLayout.Slot(index: centerIndex, offset: 0)])
          : CourierFanLayout.slots(index: focus, count: items.count)
        let layout = shelf.logicalArrangement
        let pane = layout.pane ?? .zero
        let localFrame = geometry.frame(in: .named("courier-file-dial"))
        let mouth = CGPoint(x: layout.courier.midX - pane.minX - localFrame.minX,
          y: pane.maxY - layout.courier.maxY + max(shelf.closeControlSize, shelf.expandControlSize) + shelf.iconSize / 2 - localFrame.minY)
        ZStack {
          FileDropSurface(enabled: !locked, receive: { _ in }, receiving: { _ in }, hover: shelf.hoverChanged,
            failure: { _ in }, beginDrop: { shelf.beginDrop(into: box.id) })
            .accessibilityLabel("File dial. Scroll to turn through \(items.count) files.")
            .accessibilityValue(items.isEmpty ? "Empty parcel" : "\(focus + 1) of \(items.count)")
            .accessibilityAdjustableAction { direction in advance(direction == .increment ? 1 : -1) }
          if items.isEmpty {
            Text(store.isSearching ? "No files match your search." : "Drop files here, or use Paste above.").font(.system(size: 12))
              .padding(10).background(.ultraThinMaterial, in: Capsule()).allowsHitTesting(false)
              .frame(maxHeight: .infinity, alignment: .bottom)
          }
          ForEach(slots) { slot in
            let offset = slot.offset
            let point = straight ? CourierFanLayout.straightCenter(offset: offset, size: geometry.size, count: items.count)
              : CourierFanLayout.anchoredCenter(offset: offset, origin: mouth, side: layout.side,
              radius: shelf.dialRadius, count: compact ? 1 : items.count)
            let settled = revealed || reduceMotion || staticRendering
            card(items[slot.index], compact: straight)
              .frame(width: straight ? min(76, geometry.size.width / CGFloat(max(1, min(5, items.count))) - 4) : 76,
                height: straight ? max(48, geometry.size.height - 2) : 80)
              .scaleEffect(settled ? (offset == 0 ? 1.04 : 1) : 0.4)
              .opacity(settled ? (abs(offset) > 2 ? 0 : 1) : 0)
              .position(x: settled ? point.x : mouth.x, y: settled ? point.y : mouth.y)
              .animation(Motion.fanOpen?.delay(Double(max(0, offset + 2)) * (4.0 / 30)), value: revealed)
              .animation(Motion.dialDetent, value: focus)
              .zIndex(Double(4 - abs(offset)))
              .allowsHitTesting(abs(offset) <= 2 && settled)
              .accessibilityHidden(abs(offset) > 2)
          }
        }.clipped()
      }
    }.padding(8).foregroundStyle(palette.text).coordinateSpace(name: "courier-file-dial")
      .contentShape(Rectangle())
      .background(CourierScrollRegion(scroll: turn))
      .onAppear { revealed = true }
      .onDisappear { hovered = nil; dragging = nil; preview.clear() }
      .onChange(of: items.map(\.id)) { _, _ in focus = CourierFanLayout.initialIndex(count: items.count); preview.clear() }
      .onChange(of: shelf.keyboardFocusedItem) { _, itemID in
        if let itemID, let index = items.firstIndex(where: { $0.id == itemID }) { focus = index }
      }
  }
  private func advance(_ steps: Int) {
    guard !locked else { return }
    focus = CourierFanLayout.wrappedIndex(focus + steps, count: items.count)
    hovered = nil; preview.clear()
  }
  private func turn(_ delta: CGFloat) {
    let steps = wheel.steps(delta: delta)
    if steps != 0 { advance(steps) }
  }
  private func card(_ item: ParcelItem, compact: Bool) -> some View {
      let members = store.stackMembers(of: item, in: box)
      let URLs = members.map(\.effectiveURL)
      let selected = members.contains { store.selectedItems.contains($0.id) }
      return VStack(spacing: compact ? 2 : 4) {
        ZStack(alignment: .bottomTrailing) {
          FileTypeIcon(url: item.effectiveURL, size: compact ? 24 : 32)
          if members.count > 1 {
            Text("\(members.count)").font(.system(size: 7, weight: .bold)).padding(3)
              .background(palette.accent, in: Circle()).foregroundStyle(.white)
          }
        }.frame(height: compact ? 24 : 32).allowsHitTesting(false)
          .scaleEffect(hovered == item.id || shelf.keyboardFocusedItem == item.id ? 1.08 : 1)
        Text(item.compactDisplayName).font(.system(size: compact ? 8 : 9, weight: .medium)).lineLimit(compact ? 1 : 2)
          .frame(height: compact ? 13 : 23)
          .foregroundStyle(.white).shadow(color: .black.opacity(0.9), radius: 2, y: 1)
          .help(item.effectiveName)
      }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle()).overlay {
        FileDropSurface(enabled: !locked, outgoing: store.canExport ? URLs : [],
          outgoingText: members.count == 1 ? item.inlineText : nil,
          tap: {
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true { store.toggleSelection(item.id) }
            else { shelf.openFile(item) }
          }, receive: { _ in }, receiving: { _ in }, hover: { inside in
            shelf.hoverChanged(inside)
            preview.hover(item, inside: inside)
            if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
          }, failure: { _ in }, beginDrop: { shelf.beginDrop(into: box.id) }, tracksPointer: true,
          courierMenu: { _ in shelf.fileContextMenu(for: item) },
          outgoingDragChanged: { active in
            if active { dragging = item.id }
            else if dragging == item.id { dragging = nil }
          })
          .accessibilityLabel("Open or drag \(item.effectiveName)")
      }
      .background(shelf.keyboardFocusedItem == item.id || selected ? palette.accent.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 9))
      .animation(Motion.hoverLift, value: hovered)
      .contextMenu {
        Button("Open") { shelf.openFile(item) }.disabled(locked)
        Button("Quick Look") { QuickLookController.shared.show([item.effectiveURL]) }
        Button("Copy file") { shelf.copyFiles(item: item.id) }.disabled(locked || !store.canExport)
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.effectiveURL]) }
      }
  }
}

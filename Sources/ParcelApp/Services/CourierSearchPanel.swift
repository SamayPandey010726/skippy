import AppKit
import ParcelCore
import SwiftUI

private final class CourierSearchHostingView: NSHostingView<AnyView> {
  var inside: (Bool) -> Void = { _ in }
  var keyHandler: (NSEvent) -> Bool = { _ in false }
  private var area: NSTrackingArea?
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let area { removeTrackingArea(area) }
    let next = NSTrackingArea(rect: .zero,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
    addTrackingArea(next); area = next
  }
  override func mouseEntered(with event: NSEvent) { inside(true) }
  override func mouseExited(with event: NSEvent) { inside(false) }
  override func mouseDown(with event: NSEvent) { inside(true); super.mouseDown(with: event) }
  override func rightMouseDown(with event: NSEvent) { inside(true); super.rightMouseDown(with: event) }
  override func scrollWheel(with event: NSEvent) { inside(true); super.scrollWheel(with: event) }
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func keyDown(with event: NSEvent) { if !keyHandler(event) { super.keyDown(with: event) } }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    keyHandler(event) || super.performKeyEquivalent(with: event)
  }
}

private struct CourierSearchPanelView: View {
  @ObservedObject var store: ParcelStore
  var boxID: UUID
  var skin: ParcelSkin
  var close: () -> Void
  var open: (ParcelItem) -> Void
  var menu: (ParcelItem) -> NSMenu
  @FocusState private var focused: Bool
  private var box: ParcelBox? { store.boxes.first { $0.id == boxID } }
  private var results: [ParcelItem] { box.map { store.compactItems(store.filteredItems(in: $0)) } ?? [] }
  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass").font(.system(size: 11))
        TextField("Search this parcel", text: $store.searchText)
          .textFieldStyle(.plain).font(.system(size: 11)).focused($focused)
        FileFilterMenu().environmentObject(store)
        Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).frame(width: 24, height: 24)
      }.padding(.leading, 9).background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
      HStack {
        Text(store.isSearching ? "\(results.count) result\(results.count == 1 ? "" : "s")" : "All items")
        Spacer()
        if store.isSearching { Button("Clear", action: store.clearFileSearch).buttonStyle(.plain) }
      }.font(.system(size: 9)).foregroundStyle(skin.palette.secondary)
      ScrollView {
        LazyVStack(spacing: 4) {
          ForEach(results) { item in
            let urls = box.map { store.stackMembers(of: item, in: $0).map(\.effectiveURL) } ?? []
            HStack(spacing: 7) {
              FileTypeIcon(url: item.effectiveURL, size: 24).frame(width: 26, height: 26).allowsHitTesting(false)
              Text(item.compactDisplayName).font(.system(size: 10, weight: .medium)).lineLimit(1).help(item.effectiveName)
              Spacer(minLength: 0)
              if urls.count > 1 {
                Text("\(urls.count)").font(.system(size: 8, weight: .bold)).padding(4)
                  .background(.thinMaterial, in: Circle())
              }
            }.padding(.horizontal, 7).frame(height: 38)
              .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
              .overlay {
                FileDropSurface(enabled: !store.busy, outgoing: urls, outgoingText: item.inlineText,
                  tap: { open(item) }, receive: { _ in }, receiving: { _ in }, hover: { _ in }, failure: { _ in },
                  courierMenu: { _ in menu(item) })
              }
          }
          if results.isEmpty { Text("No matching items.").font(.system(size: 10)).padding(24) }
        }
      }.scrollIndicators(.visible)
    }.padding(9).foregroundStyle(skin.palette.text)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
      .onAppear { focused = true }
      .onReceive(NotificationCenter.default.publisher(for: .parcelFocusCourierSearch)) { _ in focused = true }
  }
}

@MainActor final class CourierSearchPanelController {
  private(set) var panel: ShelfPanel?
  func show(store: ParcelStore, boxID: UUID, parent: NSPanel, skin: ParcelSkin,
            inside: @escaping (Bool) -> Void, close: @escaping () -> Void,
            open: @escaping (ParcelItem) -> Void, menu: @escaping (ParcelItem) -> NSMenu,
            keyHandler: @escaping (NSEvent) -> Bool) {
    guard let screen = parent.screen?.visibleFrame else { return }
    let size = CGSize(width: 250, height: min(390, screen.height - 24))
    let x = min(screen.maxX - size.width - 8, parent.frame.maxX + 8)
    let y = min(max(parent.frame.maxY - size.height, screen.minY + 8), screen.maxY - size.height - 8)
    let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
    let window = panel ?? ShelfPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.level = .popUpMenu; window.isFloatingPanel = true; window.hidesOnDeactivate = false
    window.isReleasedWhenClosed = false; window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = true
    window.acceptsMouseMovedEvents = true; window.becomesKeyOnlyIfNeeded = false
    let host = CourierSearchHostingView(rootView: AnyView(CourierSearchPanelView(store: store, boxID: boxID,
      skin: skin, close: close, open: open, menu: menu)))
    host.sizingOptions = []; host.inside = inside; host.keyHandler = keyHandler
    window.contentView = host; window.setFrame(frame, display: true)
    if window.parent !== parent { window.parent?.removeChildWindow(window); parent.addChildWindow(window, ordered: .above) }
    panel = window; window.makeKeyAndOrderFront(nil)
  }
  func hide() {
    guard let panel else { return }
    panel.parent?.removeChildWindow(panel); panel.orderOut(nil); panel.contentView = nil
  }
}

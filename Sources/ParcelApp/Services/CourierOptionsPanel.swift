import AppKit
import ParcelCore
import SwiftUI

private final class CourierOptionsHostingView: NSHostingView<AnyView> {
  var hover: (Bool) -> Void = { _ in }
  private var area: NSTrackingArea?
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let area { removeTrackingArea(area) }
    let next = NSTrackingArea(rect: .zero,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(next); area = next
  }
  override func mouseEntered(with event: NSEvent) { hover(true) }
  override func mouseExited(with event: NSEvent) { hover(false) }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct CourierOptionsPanelView: View {
  var parcelName: String
  var binCount: Int
  var skin: ParcelSkin
  var viewStyle: CourierViewStyle
  var setViewStyle: (CourierViewStyle) -> Void
  var paste: () -> Void
  var openBin: () -> Void
  var delete: () -> Void
  var settings: () -> Void
  var close: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Options").font(.system(size: 12, weight: .semibold))
        Spacer()
        Button(action: close) { Image(systemName: "xmark").frame(width: 24, height: 24) }.buttonStyle(.plain)
      }
      Text(parcelName).font(.system(size: 9)).foregroundStyle(skin.palette.secondary).lineLimit(1)
      action("Paste into parcel", "doc.on.clipboard", paste)
      action("Open Bin (\(binCount))", "trash", openBin)
      Divider()
      Text("File view").font(.system(size: 9)).foregroundStyle(skin.palette.secondary)
      HStack(spacing: 4) {
        style(.dial, "circle.grid.cross")
        style(.grid, "square.grid.2x2")
        style(.list, "list.bullet")
      }
      Divider()
      action("Move parcel to Bin", "trash.fill", delete, destructive: true)
      action("More settings…", "gearshape", settings)
    }
    .padding(10).foregroundStyle(skin.palette.text)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private func action(_ title: String, _ symbol: String, _ perform: @escaping () -> Void,
                      destructive: Bool = false) -> some View {
    Button {
      perform(); close()
    } label: {
      Label(title, systemImage: symbol).font(.system(size: 10, weight: .medium))
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
    }
    .buttonStyle(.plain).foregroundStyle(destructive ? Color.red : skin.palette.text)
  }

  private func style(_ style: CourierViewStyle, _ symbol: String) -> some View {
    Button { setViewStyle(style); close() } label: {
      Image(systemName: symbol).frame(maxWidth: .infinity, minHeight: 26)
        .background(viewStyle == style ? skin.palette.accent.opacity(0.2) : .clear,
          in: RoundedRectangle(cornerRadius: 8))
    }.buttonStyle(.plain).help(style.rawValue.capitalized)
  }
}

@MainActor final class CourierOptionsPanelController {
  private(set) var panel: ShelfPanel?
  func show(store: ParcelStore, boxID: UUID, parent: NSPanel, skin: ParcelSkin,
            viewStyle: CourierViewStyle, setViewStyle: @escaping (CourierViewStyle) -> Void,
            hover: @escaping (Bool) -> Void,
            paste: @escaping () -> Void, openBin: @escaping () -> Void,
            delete: @escaping () -> Void, settings: @escaping () -> Void, close: @escaping () -> Void) {
    guard let screen = parent.screen?.visibleFrame,
      let box = store.boxes.first(where: { $0.id == boxID }) else { return }
    let size = CGSize(width: 190, height: 216)
    let onRight = screen.maxX - parent.frame.maxX >= size.width + 10
    let x = onRight ? parent.frame.maxX + 8 : parent.frame.minX - size.width - 8
    let y = min(max(parent.frame.maxY - size.height, screen.minY + 8), screen.maxY - size.height - 8)
    let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
    let window = panel ?? ShelfPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.level = .popUpMenu; window.isFloatingPanel = true; window.hidesOnDeactivate = false
    window.isReleasedWhenClosed = false; window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = true
    window.becomesKeyOnlyIfNeeded = false
    let content = CourierOptionsPanelView(parcelName: box.name, binCount: store.trashedBoxes.count,
      skin: skin, viewStyle: viewStyle, setViewStyle: setViewStyle,
      paste: paste, openBin: openBin, delete: delete, settings: settings, close: close)
    let host = CourierOptionsHostingView(rootView: AnyView(content))
    host.sizingOptions = []; host.hover = hover
    window.contentView = host; window.setFrame(frame, display: true)
    if window.parent !== parent { window.parent?.removeChildWindow(window); parent.addChildWindow(window, ordered: .above) }
    panel = window; window.makeKeyAndOrderFront(nil)
  }
  func hide() {
    guard let panel else { return }
    panel.parent?.removeChildWindow(panel); panel.orderOut(nil); panel.contentView = nil
  }
}

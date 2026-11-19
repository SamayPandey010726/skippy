import AppKit
import ParcelCore
import Quartz
import SwiftUI

struct ScrollableFilePreview: NSViewRepresentable {
  var url: URL
  func makeNSView(context: Context) -> PreviewScrollView { PreviewScrollView() }
  func updateNSView(_ view: PreviewScrollView, context: Context) { view.load(url) }
  static func dismantleNSView(_ view: PreviewScrollView, coordinator: ()) { view.preview.close() }

  final class PreviewScrollView: NSScrollView {
    let preview = QLPreviewView(frame: .zero, style: .normal)!
    private var loadedURL: URL?
    override init(frame: NSRect) {
      super.init(frame: frame)
      drawsBackground = false
      hasVerticalScroller = true
      hasHorizontalScroller = true
      autohidesScrollers = false
      preview.autostarts = false
      preview.shouldCloseWithWindow = false
      documentView = preview
      setAccessibilityLabel("File preview. Scroll vertically or horizontally to explore.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func load(_ url: URL) {
      guard loadedURL != url else { return }
      loadedURL = url
      preview.previewItem = url as NSURL
      layoutSubtreeIfNeeded()
      contentView.scroll(to: CGPoint(x: 0, y: max(0, preview.frame.height - contentSize.height)))
      reflectScrolledClipView(contentView)
    }
    override func layout() {
      super.layout()
      let target = CGSize(width: max(760, contentSize.width), height: max(540, contentSize.height))
      if preview.frame.size != target { preview.setFrameSize(target) }
    }
  }
}

private final class ParcelPickerHostingView: NSHostingView<AnyView> {
  var hover: (Bool) -> Void = { _ in }
  private var pointerArea: NSTrackingArea?
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let pointerArea { removeTrackingArea(pointerArea) }
    let area = NSTrackingArea(rect: .zero,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
    addTrackingArea(area)
    pointerArea = area
  }
  override func mouseEntered(with event: NSEvent) { hover(true) }
  override func mouseExited(with event: NSEvent) { hover(false) }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct ParcelPickerTile: View {
  var box: ParcelBox
  var palette: SkinPalette
  var select: () -> Void
  var beginDrop: () -> FileDropHandler?
  @State private var dropHovered = false

  var body: some View {
    Button(action: select) {
      VStack(spacing: 5) {
        ZStack(alignment: .bottomTrailing) {
          Image(systemName: box.isShelfPinned ? "shippingbox.fill" : "shippingbox")
            .font(.system(size: 23, weight: .medium))
          Text("\(box.items.count)").font(.system(size: 8, weight: .bold)).monospacedDigit()
            .padding(3).background(palette.canvas, in: Circle()).offset(x: 6, y: 5)
        }.foregroundStyle(dropHovered ? .green : palette.accent)
        Text(box.name).font(.system(size: 10, weight: .semibold)).lineLimit(2)
          .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 24)
      }
      .padding(8).frame(width: 78, height: 78)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(dropHovered ? .green : palette.line,
        lineWidth: dropHovered ? 2 : 0.8))
      .scaleEffect(dropHovered ? 1.1 : 1)
      .shadow(color: dropHovered ? .green.opacity(0.45) : .clear, radius: 8)
      .animation(Motion.hoverLift, value: dropHovered)
    }
    .buttonStyle(.plain)
    .overlay {
      FileDropSurface(enabled: true, tap: select, receive: { _ in }, receiving: { _ in },
        hover: { dropHovered = $0 }, failure: { _ in }, beginDrop: beginDrop,
        tracksPointer: true, dragHover: { dropHovered = $0 })
        .frame(width: 78, height: 78)
    }
    .accessibilityLabel("Open or drop into parcel \(box.name)")
  }
}

@MainActor final class CourierParcelPickerController {
  private(set) var panel: ShelfPanel?

  func show(boxes: [ParcelBox], current: UUID?, parent: NSPanel,
            skin: ParcelSkin, hover: @escaping (Bool) -> Void,
            select: @escaping (UUID) -> Void,
            beginDrop: @escaping (UUID) -> FileDropHandler?) {
    let choices = boxes.filter { $0.id != current }
    guard !choices.isEmpty, let screen = parent.screen?.visibleFrame else { hide(); return }
    let width: CGFloat = 176
    let rows = CGFloat((choices.count + 1) / 2)
    let height = min(rows * 84 + 12, min(432, screen.height - 24))
    let onRight = screen.maxX - parent.frame.maxX >= width + 10
    let x = onRight ? parent.frame.maxX + 8 : parent.frame.minX - width - 8
    let y = min(max(parent.frame.maxY - height, screen.minY + 8), screen.maxY - height - 8)
    let frame = CGRect(x: x, y: y, width: width, height: height)
    let window: ShelfPanel
    if let panel { window = panel }
    else {
      window = ShelfPanel(contentRect: frame, styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.level = .popUpMenu
      window.isFloatingPanel = true
      window.becomesKeyOnlyIfNeeded = false
      window.hidesOnDeactivate = false
      window.isReleasedWhenClosed = false
      window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
      window.backgroundColor = .clear
      window.isOpaque = false
      window.hasShadow = false
      panel = window
    }
    let palette = skin.palette
    let content = ScrollView {
      LazyVGrid(columns: [GridItem(.fixed(78), spacing: 6), GridItem(.fixed(78), spacing: 6)], spacing: 6) {
        ForEach(choices) { box in
          ParcelPickerTile(box: box, palette: palette, select: { select(box.id) },
            beginDrop: { beginDrop(box.id) })
        }
      }.padding(6)
    }.scrollIndicators(.hidden).background(Color.clear)
    let host = ParcelPickerHostingView(rootView: AnyView(content))
    host.sizingOptions = []
    host.hover = hover
    window.contentView = host
    window.setFrame(frame, display: true)
    if window.parent !== parent {
      window.parent?.removeChildWindow(window)
      parent.addChildWindow(window, ordered: .above)
    }
    window.makeKeyAndOrderFront(nil)
  }

  func hide() {
    guard let panel else { return }
    panel.parent?.removeChildWindow(panel)
    panel.orderOut(nil)
    panel.contentView = nil
  }
}

private final class PreviewHostingView: NSHostingView<AnyView> {
  var hover: (Bool) -> Void = { _ in }
  var activity: () -> Void = {}
  private var pointerArea: NSTrackingArea?
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let pointerArea { removeTrackingArea(pointerArea) }
    let area = NSTrackingArea(rect: .zero,
      options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(area)
    pointerArea = area
  }
  override func mouseEntered(with event: NSEvent) { activity(); hover(true) }
  override func mouseExited(with event: NSEvent) { hover(false) }
  override func mouseMoved(with event: NSEvent) { activity() }
}

@MainActor final class CourierSidePreviewController {
  private(set) var panel: ShelfPanel?
  private var displayedID: UUID?
  private var displayedScale: CGFloat?
  func show(_ item: ParcelItem, frame: CGRect, scale: CGFloat, parent: NSPanel,
            hover: @escaping (Bool) -> Void, activity: @escaping () -> Void, close: @escaping () -> Void) {
    let window: ShelfPanel
    if let panel { window = panel }
    else {
      window = ShelfPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      window.level = .popUpMenu
      window.isFloatingPanel = true
      window.becomesKeyOnlyIfNeeded = true
      window.hidesOnDeactivate = false
      window.isReleasedWhenClosed = false
      window.isRestorable = false
      window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
      window.backgroundColor = .clear
      window.isOpaque = false
      window.hasShadow = true
      panel = window
    }
    window.setFrame(frame, display: true)
    if displayedID != item.id || displayedScale != scale || window.contentView == nil {
      let content = VStack(spacing: 8) {
        HStack(spacing: 8) {
          FileTypeIcon(url: item.effectiveURL, size: 22 * scale)
          Text(item.effectiveName).font(.system(size: 11 * scale, weight: .medium)).lineLimit(1)
            .help(item.effectiveName)
          Spacer(minLength: 0)
          Button(action: close) { Image(systemName: "xmark").frame(width: max(32, 32 * scale), height: max(32, 32 * scale)) }
            .buttonStyle(.plain).accessibilityLabel("Close file preview")
        }
        ScrollableFilePreview(url: item.effectiveURL).clipShape(RoundedRectangle(cornerRadius: 8))
      }.padding(10 * scale).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
      let host = PreviewHostingView(rootView: AnyView(content))
      host.sizingOptions = []
      host.hover = hover
      host.activity = activity
      window.contentView = host
      displayedID = item.id
      displayedScale = scale
    }
    if window.parent !== parent {
      window.parent?.removeChildWindow(window)
      parent.addChildWindow(window, ordered: .above)
    }
    window.orderFrontRegardless()
  }
  func hide() {
    guard let panel else { return }
    panel.parent?.removeChildWindow(panel)
    panel.orderOut(nil)
    panel.contentView = nil
    displayedID = nil
    displayedScale = nil
  }
}

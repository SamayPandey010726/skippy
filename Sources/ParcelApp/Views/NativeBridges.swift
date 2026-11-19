import AppKit
import ImageIO
import Quartz
import ParcelCore
import SwiftUI
import UniformTypeIdentifiers

final class NativeFileDragWriter: NSObject, NSPasteboardWriting {
  let url: URL
  init(_ url: URL) { self.url = url }
  func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    [.fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType")]
  }
  func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
    if type == .fileURL { return url.absoluteString }
    return [url.path] as NSArray
  }
}

final class NativeTextDragWriter: NSObject, NSPasteboardWriting {
  let text: String
  init(_ text: String) { self.text = text }
  func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] { [.string] }
  func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? { text }
}

struct FileDropHandler {
  var receive: ([URL]) -> Void
  var receiveText: (String) -> Void
  var receiving: (Bool) -> Void
  var failure: (String) -> Void
}

struct WindowMoveActions {
  var begin: () -> Void
  var drag: (NSEvent) -> Void
  var end: () -> Void
}

struct FileDropSurface: NSViewRepresentable {
  var enabled: Bool
  var outgoing: [URL] = []
  var outgoingText: String? = nil
  var tap: () -> Void = {}
  var receive: ([URL]) -> Void
  var receiveText: (String) -> Void = { _ in }
  var receiving: (Bool) -> Void
  var hover: (Bool) -> Void
  var willReceive: ([URL]) -> Void = { _ in }
  var failure: (String) -> Void
  var beginDrop: (() -> FileDropHandler?)? = nil
  var windowMovement: WindowMoveActions? = nil
  var tracksPointer = false
  var onScroll: ((CGFloat) -> Void)? = nil
  var dragHover: ((Bool) -> Void)? = nil
  var doubleTap: (() -> Void)? = nil
  var courierMenu: ((NSView) -> NSMenu)? = nil
  var archiveForDrag: ((@escaping (URL?) -> Void) -> Void)? = nil
  var outgoingDragChanged: (Bool) -> Void = { _ in }
  var acceptsDrops = true
  static func supports(_ board: NSPasteboard) -> Bool {
    let types: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff, .URL]
      + NSFilePromiseReceiver.readableDraggedTypes.map { .init($0) }
    return board.availableType(from: types) != nil
  }
  func makeNSView(context: Context) -> ReceivingView {
    let v = ReceivingView()
    v.registerForDraggedTypes(
      [.fileURL, .png, .tiff, .URL, .string]
        + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    return v
  }
  func updateNSView(_ view: ReceivingView, context: Context) {
    view.enabled = enabled
    view.urls = outgoing
    view.outgoingText = outgoingText
    view.tap = tap
    view.receive = receive
    view.receiveText = receiveText
    view.receiving = receiving
    view.hover = hover
    view.willReceive = willReceive
    view.failure = failure
    view.beginDrop = beginDrop
    view.windowMovement = windowMovement
    view.onScroll = onScroll
    view.dragHover = dragHover
    view.doubleTap = doubleTap
    view.courierMenu = courierMenu
    view.archiveForDrag = archiveForDrag
    view.outgoingDragChanged = outgoingDragChanged
    view.acceptsDrops = acceptsDrops
    if view.tracksPointer != tracksPointer {
      view.tracksPointer = tracksPointer
      view.updateTrackingAreas()
    }
  }
  @MainActor class ReceivingView: DragOutSurface.SendingView {
    var onScroll: ((CGFloat) -> Void)?
    var dragHover: ((Bool) -> Void)?
    override func scrollWheel(with event: NSEvent) {
      if let onScroll { onScroll(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 12)) }
      else { super.scrollWheel(with: event) }
    }
    var tracksPointer = false
    private var pointerArea: NSTrackingArea?
    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      if let pointerArea { removeTrackingArea(pointerArea); self.pointerArea = nil }
      guard tracksPointer else { return }
      let area = NSTrackingArea(rect: .zero,
        options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .enabledDuringMouseDrag], owner: self)
      addTrackingArea(area)
      pointerArea = area
    }
    override func mouseEntered(with event: NSEvent) { if tracksPointer { hover(true) } }
    override func mouseExited(with event: NSEvent) { if tracksPointer { hover(false) } }
    var receive: ([URL]) -> Void = { _ in }
    var receiveText: (String) -> Void = { _ in }
    var receiving: (Bool) -> Void = { _ in }
    var hover: (Bool) -> Void = { _ in }
    var willReceive: ([URL]) -> Void = { _ in }
    var failure: (String) -> Void = { _ in }
    var beginDrop: (() -> FileDropHandler?)?
    var acceptsDrops = true
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
      guard enabled, acceptsDrops, Self.accepts(sender.draggingPasteboard) else { return [] }
      (dragHover ?? hover)(true)
      if let urls = sender.draggingPasteboard.readObjects(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
        !urls.isEmpty
      {
        willReceive(urls)
      }
      return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
      enabled && acceptsDrops && Self.accepts(sender.draggingPasteboard) ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { (dragHover ?? hover)(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { enabled && acceptsDrops }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
      let pasteboard = sender.draggingPasteboard
      guard enabled, acceptsDrops, Self.accepts(pasteboard) else { return false }
      let handler: FileDropHandler
      if let beginDrop {
        guard let destination = beginDrop() else { return false }
        handler = destination
      } else {
        handler = FileDropHandler(
          receive: receive, receiveText: receiveText, receiving: receiving, failure: failure)
      }
      let receive = handler.receive
      let receiveText = handler.receiveText
      let receiving = handler.receiving
      let failure = handler.failure
      defer { (dragHover ?? hover)(false) }
      if let urls = pasteboard.readObjects(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty
      {
        receive(urls)
        return true
      }
      if let promises = pasteboard.readObjects(
        forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
        !promises.isEmpty
      {
        let folder = StoragePaths.received.appendingPathComponent(
          UUID().uuidString, isDirectory: true)
        do {
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
          failure(error.localizedDescription)
          return false
        }
        var remaining = promises.reduce(0) { $0 + max(1, $1.fileNames.count) }
        receiving(true)
        for promise in promises {
          let receiveCallback = receive
          let receivingCallback = receiving
          let failureCallback = failure
          promise.receivePromisedFiles(
            atDestination: folder, options: [:], operationQueue: OperationQueue.main
          ) { url, error in
            Task { @MainActor in
              if let error {
                failureCallback(
                  "Could not receive this promised file: \(error.localizedDescription)")
              } else {
                receiveCallback([url])
              }
              remaining -= 1
              if remaining == 0 { receivingCallback(false) }
            }
          }
        }
        return true
      }
      if let image = NSImage(pasteboard: pasteboard), let data = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: data),
        let png = rep.representation(using: .png, properties: [:])
      {
        let url = StoragePaths.received.appendingPathComponent(
          "Dropped image-" + UUID().uuidString + ".png")
        do {
          try png.write(to: url, options: .atomic)
          receive([url])
          return true
        } catch {
          failure(error.localizedDescription)
          return false
        }
      }
      if let text = pasteboard.string(forType: .string) ?? pasteboard.string(forType: .URL),
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        receiveText(text)
        return true
      }
      failure(
        "This app did not provide files, an image or text. Save the item as a file, then add it to Parcel."
      )
      return false
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { (dragHover ?? hover)(false) }
    private static func accepts(_ board: NSPasteboard) -> Bool {
      FileDropSurface.supports(board) || board.availableType(from: [.string]) != nil
    }
  }
}

struct DragOutSurface: NSViewRepresentable {
  var urls: [URL]
  var outgoingText: String? = nil
  var enabled: Bool = true
  var tap: () -> Void = {}
  func makeNSView(context: Context) -> SendingView { SendingView() }
  func updateNSView(_ view: SendingView, context: Context) {
    view.urls = urls
    view.outgoingText = outgoingText
    view.enabled = enabled
    view.tap = tap
  }
  @MainActor class SendingView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var outgoingText: String?
    var enabled = true
    var tap: () -> Void = {}
    var doubleTap: (() -> Void)?
    var courierMenu: ((NSView) -> NSMenu)?
    var archiveForDrag: ((@escaping (URL?) -> Void) -> Void)?
    var outgoingDragChanged: (Bool) -> Void = { _ in }
    var windowMovement: WindowMoveActions?
    private var down: NSEvent?
    private var started = false
    private var rightDown: NSEvent?
    private var rightDrag: NSEvent?
    private var preparingRightDrag = false
    private var leftDrag: NSEvent?
    private var preparingLeftDrag = false
    override func rightMouseDown(with event: NSEvent) {
      guard courierMenu != nil || archiveForDrag != nil else { super.rightMouseDown(with: event); return }
      rightDown = event; rightDrag = nil; preparingRightDrag = false
    }
    override func rightMouseDragged(with event: NSEvent) {
      guard enabled, let rightDown, let archiveForDrag else { return }
      rightDrag = event
      guard !preparingRightDrag, hypot(event.locationInWindow.x - rightDown.locationInWindow.x,
        event.locationInWindow.y - rightDown.locationInWindow.y) > 4 else { return }
      preparingRightDrag = true
      archiveForDrag { [weak self] url in
        guard let self, let url, let drag = self.rightDrag, self.rightDown != nil,
          NSEvent.pressedMouseButtons & 2 != 0 else { return }
        self.startArchiveDrag(url, event: drag)
        self.rightDown = nil; self.rightDrag = nil
      }
    }
    override func rightMouseUp(with event: NSEvent) {
      defer { rightDown = nil; rightDrag = nil }
      guard !preparingRightDrag, let menu = courierMenu?(self) else { return }
      NSApp.activate(ignoringOtherApps: true)
      menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }
    private func startArchiveDrag(_ url: URL, event: NSEvent) {
      guard FileManager.default.fileExists(atPath: url.path) else { return }
      DragMonitor.shared.suppressNextOwnDrag()
      let item = NSDraggingItem(pasteboardWriter: NativeFileDragWriter(url))
      let origin = convert(event.locationInWindow, from: nil)
      item.setDraggingFrame(Self.centeredDragFrame(at: origin, size: CGSize(width: 80, height: 80)),
        contents: NSWorkspace.shared.icon(forFile: url.path))
      outgoingDragChanged(true)
      let session = beginDraggingSession(with: [item], event: event, source: self)
      session.animatesToStartingPositionsOnCancelOrFail = true
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityPerformPress() -> Bool {
      guard enabled else { return false }
      tap()
      return true
    }
    override func mouseDown(with event: NSEvent) {
      down = event
      started = false
      leftDrag = nil
      preparingLeftDrag = false
      if enabled { windowMovement?.begin() }
    }
    override func mouseDragged(with event: NSEvent) {
      guard enabled, let down else { return }
      if preparingLeftDrag { leftDrag = event; return }
      guard !started else { return }
      guard
        hypot(
          event.locationInWindow.x - down.locationInWindow.x,
          event.locationInWindow.y - down.locationInWindow.y) > 4
      else { return }
      if let windowMovement {
        started = true
        windowMovement.drag(down)
        return
      }
      if urls.isEmpty, let archiveForDrag {
        started = true
        preparingLeftDrag = true
        leftDrag = event
        archiveForDrag { [weak self] url in
          guard let self, let url, let drag = self.leftDrag, self.down != nil,
            NSEvent.pressedMouseButtons & 1 != 0 else { return }
          self.startArchiveDrag(url, event: drag)
          self.down = nil; self.leftDrag = nil; self.preparingLeftDrag = false
        }
        return
      }
      if let outgoingText, !outgoingText.isEmpty {
        started = true
        DragMonitor.shared.suppressNextOwnDrag()
        let origin = convert(event.locationInWindow, from: nil)
        let item = NSDraggingItem(pasteboardWriter: NativeTextDragWriter(outgoingText))
        item.setDraggingFrame(Self.centeredDragFrame(at: origin, size: CGSize(width: 72, height: 42)),
          contents: NSImage(systemSymbolName: "text.quote", accessibilityDescription: "Text"))
        outgoingDragChanged(true)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        return
      }
      guard !urls.isEmpty else { return }
      let valid = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
      guard !valid.isEmpty else { return }
      started = true
      // Don't let our own drag-out summon the drop popup.
      DragMonitor.shared.suppressNextOwnDrag(allowQuickConvert: true)
      let origin = convert(event.locationInWindow, from: nil)
      let items = valid.enumerated().map { idx, url -> NSDraggingItem in
        let item = NSDraggingItem(pasteboardWriter: NativeFileDragWriter(url))
        let image =
          url.pathExtension.lowercased() == "zip"
          ? NativeArtwork.icon(size: 92) : NSWorkspace.shared.icon(forFile: url.path)
        let edge: CGFloat = valid.count == 1 ? 92 : 48
        item.setDraggingFrame(Self.centeredDragFrame(at: origin, size: CGSize(width: edge, height: edge),
          offset: CGPoint(x: CGFloat(idx % 4) * 7, y: 0)), contents: image)
        return item
      }
      outgoingDragChanged(true)
      let session = beginDraggingSession(with: items, event: event, source: self)
      session.animatesToStartingPositionsOnCancelOrFail = true
    }
    override func mouseUp(with event: NSEvent) {
      windowMovement?.end()
      if enabled && !started {
        if event.clickCount == 2, let doubleTap { doubleTap() }
        else { tap() }
      }
      down = nil
      leftDrag = nil
      preparingLeftDrag = false
    }
    func draggingSession(
      _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
      DragMonitor.shared.finishOwnDrag()
      outgoingDragChanged(false)
    }
    static func centeredDragFrame(at point: CGPoint, size: CGSize, offset: CGPoint = .zero) -> CGRect {
      CGRect(x: point.x - size.width / 2 + offset.x, y: point.y - size.height / 2 + offset.y,
        width: size.width, height: size.height)
    }
    override func resetCursorRects() {
      if enabled && (!urls.isEmpty || outgoingText != nil) { addCursorRect(bounds, cursor: .openHand) }
    }
  }
}

enum NativeArtwork {
  @MainActor static func icon(size: CGFloat) -> NSImage {
    let renderer = ImageRenderer(
      content: ParcelIllustration(sealed: true, count: 0, bounce: 0, animate: false).frame(
        width: size, height: size * 0.8))
    return renderer.nsImage ?? NSImage(
      systemSymbolName: "folder.fill", accessibilityDescription: "Parcel")!
  }
}
struct ShareButton: NSViewRepresentable {
  var items: [Any]
  var enabled: Bool = true
  var iconOnly = false
  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(
      title: iconOnly ? "" : "Share",
      image: NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)!,
      target: context.coordinator, action: #selector(Coordinator.show(_:)))
    button.bezelStyle = .rounded
    button.imagePosition = iconOnly ? .imageOnly : .imageLeading
    button.setAccessibilityLabel("Share ZIP")
    return button
  }
  func updateNSView(_ view: NSButton, context: Context) {
    context.coordinator.items = items
    view.isEnabled = enabled && !items.isEmpty
  }
  func makeCoordinator() -> Coordinator { Coordinator() }
  @MainActor final class Coordinator: NSObject {
    var items: [Any] = []
    private var picker: NSSharingServicePicker?
    @objc func show(_ sender: NSButton) {
      let p = NSSharingServicePicker(items: items)
      picker = p
      p.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
  }
}

@MainActor final class QuickLookController: NSObject, @preconcurrency QLPreviewPanelDataSource {
  static let shared = QuickLookController()
  var urls: [URL] = []
  func show(_ urls: [URL]) {
    self.urls = urls
    guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
    panel.dataSource = self
    panel.reloadData()
    panel.makeKeyAndOrderFront(nil)
  }
  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
    urls[index] as NSURL
  }
}
struct InlineFilePreview: NSViewRepresentable {
  var url: URL
  var expanded = false
  func makeNSView(context: Context) -> QLPreviewView {
    let view = QLPreviewView(frame: .zero, style: expanded ? .normal : .compact)!
    view.autostarts = false
    return view
  }
  func updateNSView(_ view: QLPreviewView, context: Context) {
    if (view.previewItem as? NSURL)?.path != url.path { view.previewItem = url as NSURL }
  }
  static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.close() }
}

struct CourierScrollRegion: NSViewRepresentable {
  var scroll: (CGFloat) -> Void
  func makeNSView(context: Context) -> Region { Region() }
  func updateNSView(_ view: Region, context: Context) { view.scroll = scroll }
  static func dismantleNSView(_ view: Region, coordinator: ()) { view.stop() }
  final class Region: NSView {
    var scroll: (CGFloat) -> Void = { _ in }
    private var monitor: Any?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      stop()
      guard window != nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
        guard let self, self.consume(event) else { return event }
        return nil
      }
    }
    func consume(_ event: NSEvent) -> Bool {
      let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
      return consume(window: event.window, location: event.locationInWindow, delta: delta, precise: event.hasPreciseScrollingDeltas)
    }
    func consume(window eventWindow: NSWindow?, location: CGPoint, delta: CGFloat, precise: Bool) -> Bool {
      guard let window, eventWindow === window, !isHiddenOrHasHiddenAncestor,
        bounds.contains(convert(location, from: nil)) else { return false }
      scroll(delta * (precise ? 1 : 12))
      return true
    }
    func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
  }
}

struct FileTypeIcon: View {
  var url: URL
  var size: CGFloat = 32
  var body: some View {
    Image(nsImage: Self.image(for: url)).resizable().scaledToFit().frame(width: size, height: size)
  }
  static func image(for url: URL) -> NSImage {
    let type = UTType(filenameExtension: url.pathExtension)
    if let type, !type.conforms(to: .image), !type.conforms(to: .movie), !type.conforms(to: .audio),
      !type.conforms(to: .directory), let application = NSWorkspace.shared.urlForApplication(toOpen: url) {
      return NSWorkspace.shared.icon(forFile: application.path)
    }
    if FileManager.default.fileExists(atPath: url.path) { return NSWorkspace.shared.icon(forFile: url.path) }
    if let type { return NSWorkspace.shared.icon(for: type) }
    return NSWorkspace.shared.icon(for: .data)
  }
}

@MainActor final class CourierHoverPreview: ObservableObject {
  @Published private(set) var item: ParcelItem?
  private var pending: Task<Void, Never>?
  private let enterDelay: Duration
  private let exitDelay: Duration
  private var hoveredID: UUID?
  private(set) var isInsidePreview = false
  init(enterDelay: Duration = .milliseconds(180), exitDelay: Duration = .milliseconds(500)) {
    self.enterDelay = enterDelay; self.exitDelay = exitDelay
  }
  func hover(_ item: ParcelItem?, inside: Bool) {
    if !inside, hoveredID != item?.id { return }
    hoveredID = inside ? item?.id : nil
    pending?.cancel()
    if !inside && isInsidePreview { return }
    let delay = inside ? enterDelay : exitDelay
    pending = Task { [weak self] in
      do { try await Task.sleep(for: delay) } catch { return }
      guard !Task.isCancelled else { return }
      self?.item = inside ? item : nil
    }
  }
  func previewHover(_ inside: Bool) {
    guard inside != isInsidePreview else { return }
    isInsidePreview = inside
    pending?.cancel()
    if !inside {
      hoveredID = nil
      hover(nil, inside: false)
    }
  }
  func focus(_ item: ParcelItem) { pending?.cancel(); pending = nil; hoveredID = item.id; self.item = item }
  func clear() { pending?.cancel(); pending = nil; hoveredID = nil; isInsidePreview = false; item = nil }
}

@MainActor final class CourierMenuAction: NSMenuItem {
  private let handler: () -> Void
  init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) {
    handler = action
    super.init(title: title, action: #selector(invoke), keyEquivalent: "")
    target = self; isEnabled = enabled
  }
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  @objc private func invoke() { handler() }
}

struct FileThumbnail: View {
  var url: URL
  var size: CGFloat = 42
  var pixelLimit: Int = 160
  @State private var image: NSImage?
  var body: some View {
    Group {
      if let image {
        Image(nsImage: image).resizable().scaledToFit()
      } else {
        Image(systemName: "doc").font(.system(size: 25, weight: .light)).foregroundStyle(Ink.moss)
      }
    }
    .frame(width: size, height: size).task(id: url.path) {
      image = nil
      let u = url
      let limit = pixelLimit
      let result = await Task.detached(priority: .utility) { () -> CGImage? in
        guard
          let source = CGImageSourceCreateWithURL(
            u as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(
          source, 0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
          ] as CFDictionary)
      }.value
      guard !Task.isCancelled else { return }
      image =
        result.map { NSImage(cgImage: $0, size: .zero) } ?? NSWorkspace.shared.icon(forFile: u.path)
    }
  }
}

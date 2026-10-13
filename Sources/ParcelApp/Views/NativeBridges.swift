import AppKit
import ImageIO
import Quartz
import SwiftUI
import UniformTypeIdentifiers

struct FileDropSurface: NSViewRepresentable {
  var enabled: Bool
  var outgoing: [URL] = []
  var tap: () -> Void = {}
  var receive: ([URL]) -> Void
  var receiveText: (String) -> Void = { _ in }
  var receiving: (Bool) -> Void
  var hover: (Bool) -> Void
  var willReceive: ([URL]) -> Void = { _ in }
  var failure: (String) -> Void
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
    view.tap = tap
    view.receive = receive
    view.receiveText = receiveText
    view.receiving = receiving
    view.hover = hover
    view.willReceive = willReceive
    view.failure = failure
  }
  @MainActor final class ReceivingView: DragOutSurface.SendingView {
    var receive: ([URL]) -> Void = { _ in }
    var receiveText: (String) -> Void = { _ in }
    var receiving: (Bool) -> Void = { _ in }
    var hover: (Bool) -> Void = { _ in }
    var willReceive: ([URL]) -> Void = { _ in }
    var failure: (String) -> Void = { _ in }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
      guard enabled else { return [] }
      hover(true)
      if let urls = sender.draggingPasteboard.readObjects(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
        !urls.isEmpty
      {
        willReceive(urls)
      }
      return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
      enabled ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { hover(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { enabled }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
      hover(false)
      guard enabled else { return false }
      let pasteboard = sender.draggingPasteboard
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
        for promise in promises {
          let receiveCallback = receive
          let receivingCallback = receiving
          let failureCallback = failure
          // Balanced: one begin per promise, one end per promise. An unbalanced
          // count would silently block Pack, Prepare and box switching.
          receivingCallback(true)
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
              receivingCallback(false)
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
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { hover(false) }
  }
}

struct DragOutSurface: NSViewRepresentable {
  var urls: [URL]
  var enabled: Bool = true
  var tap: () -> Void = {}
  func makeNSView(context: Context) -> SendingView { SendingView() }
  func updateNSView(_ view: SendingView, context: Context) {
    view.urls = urls
    view.enabled = enabled
    view.tap = tap
  }
  @MainActor class SendingView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var enabled = true
    var tap: () -> Void = {}
    private var down: NSEvent?
    private var started = false
    override func mouseDown(with event: NSEvent) {
      down = event
      started = false
    }
    override func mouseDragged(with event: NSEvent) {
      guard enabled, !started, let down, !urls.isEmpty else { return }
      guard
        hypot(
          event.locationInWindow.x - down.locationInWindow.x,
          event.locationInWindow.y - down.locationInWindow.y) > 4
      else { return }
      let valid = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
      guard !valid.isEmpty else { return }
      started = true
      // Don't let our own drag-out summon the drop popup.
      DragMonitor.shared.suppressNextOwnDrag()
      let origin = convert(event.locationInWindow, from: nil)
      let items = valid.enumerated().map { idx, url -> NSDraggingItem in
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let image =
          url.pathExtension.lowercased() == "zip"
          ? NativeArtwork.icon(size: 92) : NSWorkspace.shared.icon(forFile: url.path)
        item.setDraggingFrame(
          NSRect(
            x: origin.x + CGFloat(idx % 4) * 7, y: origin.y, width: valid.count == 1 ? 92 : 48,
            height: valid.count == 1 ? 92 : 48), contents: image)
        return item
      }
      let session = beginDraggingSession(with: items, event: event, source: self)
      session.animatesToStartingPositionsOnCancelOrFail = true
    }
    override func mouseUp(with event: NSEvent) {
      if !started { tap() }
      down = nil
    }
    func draggingSession(
      _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation { .copy }
    override func resetCursorRects() {
      if enabled && !urls.isEmpty { addCursorRect(bounds, cursor: .openHand) }
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
  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(
      title: "Share",
      image: NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)!,
      target: context.coordinator, action: #selector(Coordinator.show(_:)))
    button.bezelStyle = .rounded
    button.imagePosition = .imageLeading
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

@MainActor final class QuickLookController: NSObject, QLPreviewPanelDataSource {
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

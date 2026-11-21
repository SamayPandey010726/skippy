import AppKit
import ScreenCaptureKit
import SwiftUI

enum WorkspaceCaptureMode: String, CaseIterable, Identifiable {
  case area = "Area", window = "Window", display = "Display", multiple = "Multiple"
  var id: Self { self }
}

struct CaptureComposition {
  static func pixelRect(_ rect: CGRect, canvas: CGSize, image: CGImage) -> CGRect {
    guard canvas.width > 0, canvas.height > 0 else { return .zero }
    let scaleX = CGFloat(image.width) / canvas.width
    let scaleY = CGFloat(image.height) / canvas.height
    let pixels = CGRect(x: rect.minX * scaleX, y: rect.minY * scaleY,
      width: rect.width * scaleX, height: rect.height * scaleY).integral
    return pixels.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
  }

  static func combine(_ images: [CGImage], columns: Int) -> CGImage? {
    guard !images.isEmpty, columns > 0 else { return nil }
    let columns = min(columns, images.count)
    let rows = (images.count + columns - 1) / columns
    var widths = Array(repeating: 0, count: columns)
    var heights = Array(repeating: 0, count: rows)
    for (index, image) in images.enumerated() {
      widths[index % columns] = max(widths[index % columns], image.width)
      heights[index / columns] = max(heights[index / columns], image.height)
    }
    let width = widths.reduce(0, +), height = heights.reduce(0, +)
    guard width > 0, height > 0, width <= 16_384, height <= 16_384, width * height <= 64_000_000,
      let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    for (index, image) in images.enumerated() {
      let x = widths.prefix(index % columns).reduce(0, +)
      let top = heights.prefix(index / columns).reduce(0, +)
      context.draw(image, in: CGRect(x: x, y: height - top - image.height, width: image.width, height: image.height))
    }
    return context.makeImage()
  }

  static func overlay(_ ink: CGImage?, over image: CGImage, at rect: CGRect) -> CGImage {
    guard let ink, let context = CGContext(data: nil, width: image.width, height: image.height,
      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    context.draw(ink, in: rect)
    return context.makeImage() ?? image
  }
}

@MainActor final class ScreenCaptureWorkspace {
  static let shared = ScreenCaptureWorkspace()
  private var panel: NSPanel?
  private var working = false

  func capture(_ mode: WorkspaceCaptureMode, ink: CGImage? = nil, on screen: NSScreen? = nil,
               completion: @escaping (Result<[CGImage], Error>) -> Void) {
    guard !working, panel == nil else {
      completion(.failure(CaptureError.busy))
      return
    }
    guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
      completion(.failure(CaptureError.permission))
      return
    }
    guard let screen = screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main,
      let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
      completion(.failure(CaptureError.display))
      return
    }
    working = true
    let restore = DropPopupController.shared.beginScreenSelection()
    let restoreQuiver = SkippyQuiver.shared.suspendForCapture()
    let finish: (Result<[CGImage], Error>) -> Void = { result in
      self.panel?.orderOut(nil)
      self.panel = nil
      self.working = false
      restore()
      restoreQuiver()
      completion(result)
    }
    Task {
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID.uint32Value }) else {
          throw CaptureError.display
        }
        if mode == .window {
          let windows = content.windows.filter {
            $0.windowLayer == 0 && $0.isOnScreen && $0.frame.width > 50 && $0.frame.height > 50
              && $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier
          }
          guard !windows.isEmpty else { throw CaptureError.window }
          showWindowList(windows, screen: screen) { window in
            guard let window else { finish(.success([])); return }
            self.panel?.orderOut(nil)
            Task {
              do {
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let image = try await self.snapshot(filter, size: window.frame.size)
                let x = (display.frame.minX - window.frame.minX) * CGFloat(image.width) / window.frame.width
                let y = (window.frame.maxY - display.frame.maxY) * CGFloat(image.height) / window.frame.height
                let stampSize = CGSize(width: display.frame.width * CGFloat(image.width) / window.frame.width,
                  height: display.frame.height * CGFloat(image.height) / window.frame.height)
                let annotated = CaptureComposition.overlay(ink, over: image,
                  at: CGRect(origin: CGPoint(x: x, y: y), size: stampSize))
                finish(.success([annotated]))
              } catch { finish(.failure(error)) }
            }
          }
          return
        }
        let app = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: app, exceptingWindows: [])
        let raw = try await snapshot(filter, size: screen.frame.size)
        let image = CaptureComposition.overlay(ink, over: raw, at: CGRect(x: 0, y: 0, width: raw.width, height: raw.height))
        if mode == .display { finish(.success([image])); return }
        showOverlay(screen: screen, image: image, multiple: mode == .multiple) { finish(.success($0)) }
      } catch { finish(.failure(error)) }
    }
  }

  private func snapshot(_ filter: SCContentFilter, size: CGSize) async throws -> CGImage {
    let config = SCStreamConfiguration()
    config.showsCursor = false
    config.ignoreShadowsSingleWindow = true
    let scale = CGFloat(filter.pointPixelScale)
    config.width = max(1, Int((size.width * scale).rounded()))
    config.height = max(1, Int((size.height * scale).rounded()))
    return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
  }

  private func showOverlay(screen: NSScreen, image: CGImage, multiple: Bool, finish: @escaping ([CGImage]) -> Void) {
    let window = ShelfPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.title = "Skippy · Select regions"
    window.level = .screenSaver; window.isReleasedWhenClosed = false
    window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
    window.contentView = NSHostingView(rootView: CaptureRegionsView(image: image, multiple: multiple, finish: finish))
    window.setFrame(screen.frame, display: true)
    panel = window; window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func showWindowList(_ windows: [SCWindow], screen: NSScreen, selected: @escaping (SCWindow?) -> Void) {
    let window = ShelfPanel(contentRect: CGRect(x: screen.visibleFrame.midX - 210, y: screen.visibleFrame.midY - 175,
      width: 420, height: 350), styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "Choose a window"
    window.level = .floating; window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView:
      VStack(alignment: .leading) {
        List(windows, id: \.windowID) { candidate in
          Button {
            selected(candidate)
          } label: {
            VStack(alignment: .leading) {
              Text(candidate.owningApplication?.applicationName ?? "Application")
              Text(candidate.title ?? "Untitled window").font(.caption).foregroundStyle(.secondary)
            }
          }.buttonStyle(.plain)
        }
        Button("Cancel") { selected(nil) }.keyboardShortcut(.cancelAction)
      }.padding(14))
    panel = window; window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private enum CaptureError: LocalizedError {
    case permission, display, window, busy
    var errorDescription: String? {
      switch self {
      case .permission: "Allow Screen Recording for Skippy in System Settings, then retry."
      case .display: "The selected display is unavailable."
      case .window: "No other app windows are available."
      case .busy: "Finish the current capture first."
      }
    }
  }
}

private struct CaptureRegionsView: View {
  let image: CGImage
  let multiple: Bool
  let finish: ([CGImage]) -> Void
  @State private var selected: [CGRect] = []
  @State private var draft: CGRect?

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .top) {
        Image(decorative: image, scale: 1).resizable()
          .frame(width: geometry.size.width, height: geometry.size.height)
        Canvas { context, size in
          let regions = selected + (draft.map { [$0] } ?? [])
          context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.39)))
          for (index, rect) in regions.enumerated() {
            context.drawLayer { layer in
              layer.clip(to: Path(rect))
              layer.draw(Image(decorative: image, scale: 1), in: CGRect(origin: .zero, size: size))
            }
            let selection = Path(roundedRect: rect, cornerRadius: 5)
            context.stroke(selection, with: .color(Ink.green), lineWidth: 3)
            context.stroke(selection, with: .color(.white), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            let badge = CGRect(x: rect.minX - 4, y: rect.minY - 8, width: 22, height: 18)
            context.fill(Path(roundedRect: badge, cornerRadius: 5), with: .color(Ink.green))
            context.draw(Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white),
              at: CGPoint(x: badge.midX, y: badge.midY))
          }
        }.contentShape(Rectangle())
          .gesture(DragGesture(minimumDistance: 3).onChanged { value in
            draft = CGRect(x: min(value.startLocation.x, value.location.x),
              y: min(value.startLocation.y, value.location.y),
              width: abs(value.location.x - value.startLocation.x),
              height: abs(value.location.y - value.startLocation.y))
          }.onEnded { _ in
            guard let draft, draft.width >= 4, draft.height >= 4 else { self.draft = nil; return }
            if selected.count < 24 { selected.append(draft) }
            self.draft = nil
            if !multiple { export(in: geometry.size) }
          })
        HStack {
          Text(multiple ? "Drag each region" : "Drag to capture an area")
          if multiple {
            Button("Undo") { if !selected.isEmpty { selected.removeLast() } }.disabled(selected.isEmpty)
            Button("Done (\(selected.count))") { export(in: geometry.size) }
              .keyboardShortcut(.defaultAction).disabled(selected.isEmpty)
          }
          Button("Cancel") { finish([]) }.keyboardShortcut(.cancelAction)
        }.padding(9).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
          .padding(.top, 42)
      }
      .clipped()
    }.preferredColorScheme(.dark)
  }

  private func export(in size: CGSize) {
    finish(selected.compactMap { image.cropping(to: CaptureComposition.pixelRect($0, canvas: size, image: image)) })
  }
}

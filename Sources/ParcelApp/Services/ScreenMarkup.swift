import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class ScreenMarkupController: ObservableObject {
  static let shared = ScreenMarkupController()
  private var panel: NSPanel?
  private var resumePanel: NSPanel?
  private var colourPanelLevel: NSWindow.Level?

  func open() {
    guard panel == nil, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
    let window = ShelfPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.level = .screenSaver
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.isReleasedWhenClosed = false
    window.title = "Skippy · Markup canvas"
    window.contentView = NSHostingView(rootView: ScreenMarkupView(
      close: { [weak self] in self?.close() },
      interact: { [weak self] in self?.interact(on: screen) },
      capture: { [weak self] mode, artwork in self?.capture(mode, artwork: artwork, screen: screen) }))
    panel = window
    colourPanelLevel = NSColorPanel.shared.level
    NSColorPanel.shared.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
    window.makeKeyAndOrderFront(nil)
  }

  func close() {
    if let colourPanelLevel {
      NSColorPanel.shared.orderOut(nil)
      NSColorPanel.shared.level = colourPanelLevel
      self.colourPanelLevel = nil
    }
    resumePanel?.orderOut(nil); resumePanel = nil
    panel?.orderOut(nil); panel = nil
  }

  private func interact(on screen: NSScreen) {
    guard let panel else { return }
    panel.ignoresMouseEvents = true
    let bar = ShelfPanel(contentRect: CGRect(x: screen.visibleFrame.maxX - 164, y: screen.visibleFrame.maxY - 44,
      width: 152, height: 38), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    bar.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
    bar.isReleasedWhenClosed = false; bar.isOpaque = false; bar.backgroundColor = .clear
    bar.contentView = NSHostingView(rootView: Button("Resume drawing") { [weak self] in
      self?.resumePanel?.orderOut(nil); self?.resumePanel = nil
      self?.panel?.ignoresMouseEvents = false
      self?.panel?.makeKeyAndOrderFront(nil)
    }.padding(7).background(.regularMaterial, in: Capsule()))
    resumePanel = bar; bar.orderFrontRegardless()
  }

  private func capture(_ mode: WorkspaceCaptureMode, artwork: CGImage?, screen: NSScreen) {
    NSColorPanel.shared.orderOut(nil)
    panel?.orderOut(nil)
    ScreenCaptureWorkspace.shared.capture(mode, ink: artwork, on: screen) { [weak self] result in
      self?.panel?.makeKeyAndOrderFront(nil)
      NotchToolStore.shared.acceptCaptures(result)
    }
  }
}

private enum MarkupTool: String, CaseIterable, Identifiable {
  case pen, highlighter, line, rectangle, ellipse, eraser
  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .pen: "pencil.tip"; case .highlighter: "highlighter"; case .line: "line.diagonal"
    case .rectangle: "rectangle"; case .ellipse: "circle"; case .eraser: "eraser"
    }
  }
}

private struct MarkupStroke: Identifiable {
  let id = UUID()
  var tool: MarkupTool
  var points: [CGPoint]
  var color: Color
  var width: CGFloat
}

private struct ScreenMarkupView: View {
  var close: () -> Void
  var interact: () -> Void
  var capture: (WorkspaceCaptureMode, CGImage?) -> Void
  @State private var tool: MarkupTool = .pen
  @State private var color: Color = .red
  @State private var width: CGFloat = 4
  @State private var strokes: [MarkupStroke] = []
  @State private var current: MarkupStroke?
  @State private var history: [[MarkupStroke]] = []
  @State private var future: [[MarkupStroke]] = []

  @State private var canvasSize = CGSize.zero
  @State private var exportError: String?
  @Environment(\.displayScale) private var displayScale

  private var artwork: some View {
      Canvas { context, _ in
        for stroke in strokes + (current.map { [$0] } ?? []) {
          guard let first = stroke.points.first, let last = stroke.points.last else { continue }
          var path = Path()
          switch stroke.tool {
          case .pen, .highlighter, .eraser:
            path.move(to: first)
            for point in stroke.points.dropFirst() { path.addLine(to: point) }
          case .line:
            path.move(to: first); path.addLine(to: last)
          case .rectangle, .ellipse:
            let rect = CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
              width: abs(first.x - last.x), height: abs(first.y - last.y))
            if stroke.tool == .rectangle { path.addRect(rect) } else { path.addEllipse(in: rect) }
          }
          context.blendMode = stroke.tool == .eraser ? .destinationOut : .normal
          context.stroke(path, with: .color(stroke.color.opacity(stroke.tool == .highlighter ? 0.35 : 1)),
            style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
        }
      }
  }

  @MainActor private func exportPNG() {
    let panel = NSSavePanel()
    panel.level = .screenSaver
    panel.nameFieldStringValue = "Skippy markup.png"
    panel.allowedContentTypes = [.png]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      guard let image = renderArtwork(),
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
      }
      try data.write(to: url, options: .atomic)
    } catch { exportError = error.localizedDescription }
  }

  @MainActor private func renderArtwork() -> CGImage? {
    let renderer = ImageRenderer(content: artwork.frame(width: canvasSize.width, height: canvasSize.height))
    renderer.scale = displayScale
    return renderer.cgImage
  }

  private func checkpoint() {
    history.append(strokes)
    if history.count > 40 { history.removeFirst() }
    future.removeAll()
  }

  var body: some View {
    ZStack(alignment: .top) {
      Color.black.opacity(0.001).contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
          if current == nil { current = MarkupStroke(tool: tool, points: [value.startLocation], color: color, width: width) }
          current?.points.append(value.location)
        }.onEnded { _ in
          if let current { checkpoint(); strokes.append(current) }
          current = nil
        })
      artwork.allowsHitTesting(false)

      HStack(spacing: 8) {
        ForEach(MarkupTool.allCases) { option in
          Button {
            if tool != option {
              tool = option
              width = option == .eraser ? 24 : (option == .highlighter ? 14 : 4)
            }
          } label: { Image(systemName: option.symbol).frame(width: 24, height: 24) }
            .buttonStyle(.plain).background(tool == option ? Color.accentColor.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .help(option.rawValue.capitalized)
        }
        Divider().frame(height: 20)
        ColorPicker("Colour", selection: $color, supportsOpacity: false).labelsHidden().frame(width: 28)
        Slider(value: $width, in: 1...40).frame(width: 66).accessibilityLabel("Stroke width")
        Button("Undo") {
          if let snapshot = history.popLast() { future.append(strokes); strokes = snapshot }
        }.keyboardShortcut("z").disabled(history.isEmpty)
        Button("Redo") {
          if let snapshot = future.popLast() { history.append(strokes); strokes = snapshot }
        }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(future.isEmpty)
        Button("Clear") { checkpoint(); strokes.removeAll() }.disabled(strokes.isEmpty)
        Button("Interact", action: interact).help("Keep the ink visible while working in the apps underneath")
        Menu("Capture") {
          ForEach(WorkspaceCaptureMode.allCases) { mode in
            Button(mode.rawValue) { capture(mode, renderArtwork()) }
          }
        }.fixedSize()
        Button("Save PNG…", action: exportPNG).disabled(strokes.isEmpty)
        Button("Done", action: close).keyboardShortcut(.escape, modifiers: [])
      }
      .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
      .padding(.top, 40)
    }
    .background(GeometryReader { geo in
      Color.clear.onAppear { canvasSize = geo.size }.onChange(of: geo.size) { _, size in canvasSize = size }
    })
    .alert("Could not save markup", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
      Button("OK") { exportError = nil }
    } message: { Text(exportError ?? "") }
  }
}

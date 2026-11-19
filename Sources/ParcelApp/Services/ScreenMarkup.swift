import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class ScreenMarkupController: ObservableObject {
  static let shared = ScreenMarkupController()
  private var panel: NSPanel?

  func open() {
    guard panel == nil, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
    let window = ShelfPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.level = .screenSaver
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: ScreenMarkupView(close: { [weak self] in self?.close() }))
    panel = window
    window.makeKeyAndOrderFront(nil)
  }

  func close() { panel?.orderOut(nil); panel = nil }
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
}

private struct ScreenMarkupView: View {
  var close: () -> Void
  @State private var tool: MarkupTool = .pen
  @State private var color: Color = .red
  @State private var strokes: [MarkupStroke] = []
  @State private var current: MarkupStroke?

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
            style: StrokeStyle(lineWidth: stroke.tool == .eraser ? 24 : (stroke.tool == .highlighter ? 14 : 3), lineCap: .round, lineJoin: .round))
        }
      }
  }

  @MainActor private func exportPNG() {
    let panel = NSSavePanel()
    panel.level = .screenSaver
    panel.nameFieldStringValue = "Skippy markup.png"
    panel.allowedContentTypes = [.png]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let renderer = ImageRenderer(content: artwork.frame(width: canvasSize.width, height: canvasSize.height))
    renderer.scale = displayScale
    do {
      guard let image = renderer.cgImage,
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
      }
      try data.write(to: url, options: .atomic)
    } catch { exportError = error.localizedDescription }
  }

  var body: some View {
    ZStack(alignment: .top) {
      Color.black.opacity(0.001).contentShape(Rectangle())
    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
      if current == nil { current = MarkupStroke(tool: tool, points: [value.startLocation], color: color) }
      current?.points.append(value.location)
    }.onEnded { _ in
      if let current { strokes.append(current) }
      current = nil
    })
      artwork.allowsHitTesting(false)

      HStack(spacing: 8) {
        ForEach(MarkupTool.allCases) { option in
          Button { tool = option } label: { Image(systemName: option.symbol).frame(width: 24, height: 24) }
            .buttonStyle(.plain).background(tool == option ? Color.accentColor.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .help(option.rawValue.capitalized)
        }
        Divider().frame(height: 20)
        ColorPicker("Colour", selection: $color, supportsOpacity: false).labelsHidden().frame(width: 28)
        Button("Undo") { if !strokes.isEmpty { strokes.removeLast() } }.disabled(strokes.isEmpty)
        Button("Clear") { strokes.removeAll() }.disabled(strokes.isEmpty)
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

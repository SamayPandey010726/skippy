import AppKit
import ParcelCore

enum QuickConvertAppearance: String, CaseIterable, Identifiable {
  case glass, black
  var id: String { rawValue }
  var label: String { self == .glass ? "Glass" : "Pure black" }
}

enum QuickConvertAction: String, CaseIterable, Identifiable, Sendable {
  case jpeg, png, heic, pdf, searchableWord, recognizedText, pngPages, jpegPages, compactVideo
  case excelWorkbook, csv, tsv, spreadsheetPDF
  var id: String { rawValue }
  var label: String {
    switch self {
    case .jpeg: return "JPEG"
    case .png: return "PNG"
    case .heic: return "HEIC"
    case .pdf: return "PDF"
    case .searchableWord: return "Word"
    case .recognizedText: return "Text"
    case .pngPages: return "PNG pages"
    case .jpegPages: return "JPEG pages"
    case .compactVideo: return "Smaller MP4"
    case .excelWorkbook: return "Excel"
    case .csv: return "CSV"
    case .tsv: return "TSV"
    case .spreadsheetPDF: return "Table PDF"
    }
  }
  var symbol: String {
    switch self {
    case .jpeg, .png, .heic: return "photo"
    case .pdf: return "doc.richtext"
    case .searchableWord: return "doc.text"
    case .recognizedText: return "text.viewfinder"
    case .pngPages, .jpegPages: return "photo.stack"
    case .compactVideo: return "film"
    case .excelWorkbook: return "tablecells"
    case .csv, .tsv: return "text.alignleft"
    case .spreadsheetPDF: return "doc.richtext"
    }
  }
  static func available(for urls: [URL]) -> [QuickConvertAction] {
    guard !urls.isEmpty else { return [] }
    let images = urls.allSatisfy(ImagePipeline.canPrepare)
    let pdfs = urls.allSatisfy { $0.pathExtension.lowercased() == "pdf" }
    let readable = urls.allSatisfy { ImagePipeline.canPrepare($0) || $0.pathExtension.lowercased() == "pdf" }
    let videos = urls.allSatisfy(VideoPipeline.canPrepare)
    let documents = urls.allSatisfy { ["doc", "docx", "rtf", "rtfd", "txt"].contains($0.pathExtension.lowercased()) }
    let spreadsheets = urls.allSatisfy(SpreadsheetTransformPipeline.canTransform)
    let formats = Set(urls.map { $0.pathExtension.lowercased() })
    func excludingCurrent(_ actions: [QuickConvertAction]) -> [QuickConvertAction] {
      guard formats.count == 1, let source = formats.first else { return actions }
      return actions.filter { action in
        switch action {
        case .jpeg: return !["jpg", "jpeg"].contains(source)
        case .png: return source != "png"
        case .heic: return !["heic", "heif"].contains(source)
        case .pdf: return source != "pdf"
        case .excelWorkbook: return source != "xlsx"
        case .csv: return source != "csv"
        case .tsv: return source != "tsv"
        default: return true
        }
      }
    }
    if images { return excludingCurrent([.jpeg, .png, .heic, .pdf, .searchableWord, .recognizedText]) }
    if pdfs { return [.searchableWord, .recognizedText, .pngPages, .jpegPages] }
    if readable { return [.searchableWord, .recognizedText] }
    if videos { return [.compactVideo] }
    if documents { return [.pdf] }
    if spreadsheets {
      return excludingCurrent([.excelWorkbook, .csv, .tsv, .spreadsheetPDF])
    }
    return []
  }
}

struct QuickConversionResult: Sendable {
  let url: URL
  let ownedRoot: URL
}

enum QuickConversionPipeline {
  static func convert(
    source: URL, action: QuickConvertAction, token: CancellationToken
  ) async throws -> QuickConversionResult {
    switch action {
    case .jpeg, .png, .heic:
      var recipe = ImageRecipe()
      recipe.format = action == .jpeg ? .jpeg : action == .png ? .png : .heic
      recipe.maximumDimension = 0
      recipe.quality = 0.9
      recipe.flattenTransparency = action == .jpeg
      let result = try ImagePipeline.prepare(source: source, recipe: recipe, token: token)
      return QuickConversionResult(url: result.url, ownedRoot: result.url.deletingLastPathComponent())
    case .compactVideo:
      let root = StoragePaths.prepared.appendingPathComponent(UUID().uuidString, isDirectory: true)
      do {
        let result = try await VideoPipeline.prepare(
          source: source, recipe: VideoRecipe(maximumDimension: 1280, quality: .balanced),
          token: token, directory: root)
        let ext = result.url.pathExtension
        let stem = NamePolicy.safeArchiveStem(source.deletingPathExtension().lastPathComponent)
        let named = root.appendingPathComponent(stem + " smaller." + ext)
        try FileManager.default.moveItem(at: result.url, to: named)
        return QuickConversionResult(url: named, ownedRoot: root)
      } catch {
        _ = StoragePaths.deleteOwned(root)
        throw error
      }
    case .pdf, .searchableWord, .recognizedText, .pngPages, .jpegPages,
      .excelWorkbook, .csv, .tsv, .spreadsheetPDF:
      let kind: DocumentTransformKind
      switch action {
      case .pdf:
        kind = ["doc", "docx", "rtf", "rtfd", "txt"].contains(source.pathExtension.lowercased())
          ? .documentToPDF : .imagesToPDF
      case .searchableWord: kind = .searchableWord
      case .recognizedText: kind = .recognizedText
      case .pngPages: kind = .pdfToPNG
      case .jpegPages: kind = .pdfToJPEG
      case .excelWorkbook: kind = .spreadsheetXLSX
      case .csv: kind = .spreadsheetCSV
      case .tsv: kind = .spreadsheetTSV
      case .spreadsheetPDF: kind = .spreadsheetPDF
      default: fatalError("Mapped above")
      }
      let result = try await DocumentTransformPipeline.transform(source: source, kind: kind, token: token)
      return QuickConversionResult(url: result.url, ownedRoot: result.ownedRoot)
    }
  }
}

struct DragConvertGeometry {
  var count: Int
  static let headerHeight: CGFloat = 32
  static let inset: CGFloat = 8
  static let gap: CGFloat = 6
  func center(for index: Int, in bounds: CGRect) -> CGPoint {
    let rect = targetRect(for: index, in: bounds)
    return CGPoint(x: rect.midX, y: rect.midY)
  }
  func targetRect(for index: Int, in bounds: CGRect) -> CGRect {
    guard count > 0 else { return .zero }
    let available = bounds.width - Self.inset * 2 - Self.gap * CGFloat(max(0, count - 1))
    let width = available / CGFloat(count)
    return CGRect(x: Self.inset + CGFloat(index) * (width + Self.gap), y: Self.inset,
      width: width, height: max(0, bounds.height - Self.headerHeight - Self.inset * 2))
  }
  static func centerRect(in bounds: CGRect) -> CGRect {
    bounds.insetBy(dx: 12, dy: 12)
  }
  func index(at point: CGPoint, in bounds: CGRect) -> Int? {
    (0..<count).first { targetRect(for: $0, in: bounds).contains(point) }
  }
  func sectorPath(for index: Int, in bounds: CGRect) -> NSBezierPath {
    NSBezierPath(roundedRect: targetRect(for: index, in: bounds), xRadius: 14, yRadius: 14)
  }
}

@MainActor final class DragConvertController {
  static let shared = DragConvertController()
  private var panel: NSPanel?
  private var wheel: DragConvertView?
  private weak var store: ParcelStore?
  private weak var material: NSVisualEffectView?
  private var generation = 0
  private var announcedVisible = false
  private(set) var converting = false
  var onVisibilityChanged: ((Bool) -> Void)?
  var appearance: QuickConvertAppearance = .glass { didSet { applyAppearance() } }

  func install(store: ParcelStore) { self.store = store }

  @discardableResult func present(urls: [URL], at point: CGPoint) -> Bool {
    guard !converting, !urls.isEmpty else { return false }
    let actions = RecentActionStore.shared.prioritize(QuickConvertAction.available(for: urls))
    guard !actions.isEmpty else { dismiss(); return false }
    let panel = panel ?? makePanel()
    applyAppearance()
    let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    guard let frame = screen?.visibleFrame else { return false }
    let size = CGSize(width: min(620, max(290, CGFloat(actions.count) * 92 + 16)), height: 108)
    let origin = CGPoint(
      x: min(max(point.x - size.width / 2, frame.minX), frame.maxX - size.width),
      y: min(max(point.y - size.height / 2, frame.minY), frame.maxY - size.height))
    panel.setFrame(CGRect(origin: origin, size: size), display: false)
    wheel?.configure(urls: urls, actions: actions, recent: actions.first.flatMap {
      RecentActionStore.shared.isRecent($0) ? $0 : nil
    })
    wheel?.onChoose = { [weak self] action, files in self?.choose(action, files: files) }
    panel.alphaValue = 1
    setAnnouncedVisible(true)
    panel.orderFrontRegardless()
    wheel?.animateIn()
    return true
  }

  func dragEnded() {
    guard !converting else { return }
    dismiss()
  }

  private func choose(_ action: QuickConvertAction, files: [URL]) {
    guard let store, !converting else { return }
    converting = true
    RecentActionStore.shared.record(
      id: "convert.\(action.rawValue)", title: action.label, symbol: action.symbol)
    generation += 1
    let stamp = generation
    wheel?.showWorking(action: action, count: files.count)
    store.quickConvert(files, action: action) { [weak self] count, error in
      guard let self, self.generation == stamp else { return }
      self.converting = false
      if let error {
        self.wheel?.showFailure(error)
        self.retract(after: 4)
      } else {
        self.wheel?.showSuccess(count: count)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .drawCompleted)
        self.retract(after: 1.6)
      }
    }
  }

  private func retract(after delay: TimeInterval) {
    generation += 1
    let stamp = generation
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self, self.generation == stamp else { return }
      self.dismiss()
    }
  }

  private func dismiss() {
    generation += 1
    converting = false
    guard let panel, panel.isVisible else {
      setAnnouncedVisible(false)
      return
    }
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      panel.orderOut(nil)
      setAnnouncedVisible(false)
    } else {
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.14
        panel.animator().alphaValue = 0
      }, completionHandler: { [weak self] in
        MainActor.assumeIsolated {
          panel.orderOut(nil)
          panel.alphaValue = 1
          self?.setAnnouncedVisible(false)
        }
      })
    }
  }

  private func setAnnouncedVisible(_ visible: Bool) {
    guard announcedVisible != visible else { return }
    announcedVisible = visible
    onVisibilityChanged?(visible)
  }

  private func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: CGRect(x: 0, y: 0, width: 500, height: 108),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .popUpMenu
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.hidesOnDeactivate = false
    let material = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
    material.material = .hudWindow
    material.blendingMode = .behindWindow
    material.state = .active
    material.wantsLayer = true
    material.layer?.cornerRadius = 22
    material.layer?.masksToBounds = true
    let wheel = DragConvertView(frame: material.bounds)
    wheel.autoresizingMask = [.width, .height]
    material.addSubview(wheel)
    panel.contentView = material
    self.material = material
    self.wheel = wheel
    self.panel = panel
    return panel
  }
  private func applyAppearance() {
    material?.material = appearance == .glass ? .hudWindow : .underWindowBackground
    material?.layer?.backgroundColor = appearance == .black
      ? NSColor.black.cgColor : NSColor.clear.cgColor
    wheel?.solidBlack = appearance == .black
  }
}

@MainActor final class DragConvertView: NSView {
  var onChoose: ((QuickConvertAction, [URL]) -> Void)?
  private var urls: [URL] = []
  private var actions: [QuickConvertAction] = []
  private var recent: QuickConvertAction?
  private var highlighted: Int? { didSet { if oldValue != highlighted { feedback(); needsDisplay = true } } }
  private enum State { case choosing, working(String), success(Int), failure(String) }
  private var state = State.choosing { didSet { needsDisplay = true } }
  var solidBlack = false { didSet { needsDisplay = true } }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("com.apple.finder.node")])
  }
  required init?(coder: NSCoder) { fatalError("Not supported") }

  func configure(urls: [URL], actions: [QuickConvertAction], recent: QuickConvertAction?) {
    self.urls = urls
    self.actions = actions
    self.recent = recent
    highlighted = nil
    state = .choosing
    needsDisplay = true
  }
  func showWorking(action: QuickConvertAction, count: Int) {
    state = .working("Making \(count == 1 ? "a" : "\(count)") \(action.label) \(count == 1 ? "copy" : "copies")…")
  }
  func showSuccess(count: Int) { state = .success(count) }
  func showFailure(_ message: String) { state = .failure(message) }

  func animateIn() {
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer else { return }
    let scale = CASpringAnimation(keyPath: "transform.scale")
    scale.fromValue = 0.82; scale.toValue = 1; scale.mass = 0.8; scale.stiffness = 190; scale.damping = 17
    scale.duration = scale.settlingDuration
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.16
    layer.add(scale, forKey: "parcel-convert-bloom")
    layer.add(fade, forKey: "parcel-convert-fade")
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    (solidBlack ? NSColor.black : NSColor.black.withAlphaComponent(0.22)).setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 21, yRadius: 21).fill()
    switch state {
    case .choosing: drawChoices()
    case .working(let text): drawCenter(symbol: "arrow.triangle.2.circlepath", title: "Converting", detail: text, color: .systemOrange)
    case .success(let count): drawCenter(symbol: "checkmark.circle.fill", title: "Ready", detail: "\(count) \(count == 1 ? "copy" : "copies") added to Skippy", color: .systemGreen)
    case .failure(let text): drawCenter(symbol: "exclamationmark.triangle.fill", title: "Needs a look", detail: text, color: .systemOrange)
    }
  }

  private func drawChoices() {
    let geometry = DragConvertGeometry(count: actions.count)
    for index in actions.indices {
      let selected = highlighted == index
      let path = geometry.sectorPath(for: index, in: bounds)
      (selected ? NSColor.systemOrange.withAlphaComponent(0.92) : NSColor.controlBackgroundColor.withAlphaComponent(0.55)).setFill()
      path.fill()
      NSColor.white.withAlphaComponent(0.14).setStroke(); path.lineWidth = 1; path.stroke()
      let rect = geometry.targetRect(for: index, in: bounds).offsetBy(dx: 0, dy: selected ? 2 : 0)
      if let image = NSImage(systemSymbolName: actions[index].symbol, accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
          .applying(.init(hierarchicalColor: .white.withAlphaComponent(selected ? 1 : 0.88)))
        image.withSymbolConfiguration(config)?.draw(in: CGRect(x: rect.midX - 9, y: rect.midY + 2, width: 18, height: 18))
      }
      draw(actions[index].label, in: CGRect(x: rect.minX + 3, y: rect.minY + 7, width: rect.width - 6, height: 14),
           size: 10, weight: .semibold, color: selected ? .white : .labelColor)
      if actions[index] == recent {
        draw("RECENT", in: CGRect(x: rect.minX + 4, y: rect.maxY - 15, width: rect.width - 8, height: 10),
          size: 7, weight: .bold, color: selected ? .white : .secondaryLabelColor)
      }
    }
    let source = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
    draw("Convert \(source)", in: CGRect(x: 14, y: bounds.maxY - 27, width: bounds.width - 28, height: 16),
      size: 11, weight: .semibold, color: .labelColor)
  }

  private func drawCenter(symbol: String, title: String, detail: String, color: NSColor) {
    let rect = DragConvertGeometry.centerRect(in: bounds)
    NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill()
    if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
      let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        .applying(.init(hierarchicalColor: color))
      image.withSymbolConfiguration(configuration)?
        .draw(in: CGRect(x: rect.minX + 14, y: rect.midY - 10, width: 20, height: 20))
    }
    draw(title, in: CGRect(x: rect.minX + 42, y: rect.midY + 1, width: rect.width - 54, height: 16), size: 11, weight: .bold, color: color)
    draw(detail, in: CGRect(x: rect.minX + 42, y: rect.midY - 17, width: rect.width - 54, height: 16), size: 9, weight: .regular, color: .secondaryLabelColor)
  }

  private func draw(_ string: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineBreakMode = .byTruncatingMiddle
    string.draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender); return highlighted == nil ? [] : .copy }
  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender); return highlighted == nil ? [] : .copy }
  override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = nil }
  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { highlighted != nil }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard case .choosing = state, let highlighted, actions.indices.contains(highlighted) else { return false }
    onChoose?(actions[highlighted], urls)
    return true
  }
  private func update(_ sender: NSDraggingInfo) {
    guard case .choosing = state else { return }
    highlighted = DragConvertGeometry(count: actions.count).index(at: sender.draggingLocation, in: bounds)
  }
  private func feedback() {
    guard highlighted != nil else { return }
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
  }
}

import AppKit
import SwiftUI

enum ClipboardEntryKind: String, Codable, CaseIterable, Identifiable {
  case text, image, file
  var id: String { rawValue }
  var label: String { rawValue.capitalized }
  var symbol: String {
    switch self { case .text: "text.quote"; case .image: "photo"; case .file: "doc" }
  }
}

struct ClipboardEntry: Codable, Identifiable, Equatable {
  var id = UUID()
  var kind: ClipboardEntryKind
  var createdAt = Date()
  var text: String?
  var paths: [String] = []
  var title: String
  var detail: String
  var dragText: String? { kind == .text ? text : nil }
  var dragURLs: [URL] { paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) } }
  var linkURLs: [URL] {
    kind == .text ? LinkShortener.links(in: text ?? "").filter { $0.host?.lowercased() != "da.gd" } : []
  }
}

@MainActor final class ClipboardHistoryStore: ObservableObject {
  static let shared = ClipboardHistoryStore()
  @Published private(set) var entries: [ClipboardEntry] = []
  @Published var captureEnabled: Bool {
    didSet {
      if persistsHistory { UserDefaults.standard.set(captureEnabled, forKey: "skippy.clipboard.capture") }
      changeCount = NSPasteboard.general.changeCount
    }
  }
  @Published var search = ""
  @Published var filter: ClipboardEntryKind?
  private var timer: Timer?
  private var changeCount = NSPasteboard.general.changeCount
  private let historyURL = StoragePaths.root.appendingPathComponent("clipboard-history.json")
  private let persistsHistory: Bool

  init(persist: Bool = true) {
    persistsHistory = persist
    captureEnabled = persist ? (UserDefaults.standard.object(forKey: "skippy.clipboard.capture") as? Bool ?? true) : true
  }

  var filtered: [ClipboardEntry] {
    entries.filter { Self.matches($0, search: search, filter: filter) }
  }

  static func matches(_ entry: ClipboardEntry, search: String, filter: ClipboardEntryKind?, now: Date = Date()) -> Bool {
    guard filter == nil || entry.kind == filter else { return false }
    let words = search.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    return words.allSatisfy { word in
      if word == "text" || word == "words" { return entry.kind == .text }
      if word == "image" || word == "images" || word == "photo" { return entry.kind == .image }
      if word == "file" || word == "files" { return entry.kind == .file }
      if word == "today" { return Calendar.current.isDate(entry.createdAt, inSameDayAs: now) }
      return (entry.title + " " + entry.detail + " " + (entry.text ?? "")).localizedCaseInsensitiveContains(word)
    }
  }

  func start() {
    guard timer == nil else { return }
    if persistsHistory { load() }
    capture(NSPasteboard.general)
    let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.poll() }
    }
    timer.tolerance = 0.08
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func copy(_ entry: ClipboardEntry) {
    let board = NSPasteboard.general
    board.clearContents()
    switch entry.kind {
    case .text:
      if let text = entry.text { board.setString(text, forType: .string) }
    case .file:
      board.writeObjects(entry.dragURLs as [NSURL])
    case .image:
      if let url = entry.dragURLs.first, let image = NSImage(contentsOf: url) { board.writeObjects([image]) }
    }
    changeCount = board.changeCount
    Toaster.shared.copied(entry.kind.label)
  }

  func remove(_ id: UUID) {
    entries.removeAll { $0.id == id }
    save()
  }

  func cycleFilter() {
    let values: [ClipboardEntryKind?] = [nil] + ClipboardEntryKind.allCases.map(Optional.some)
    let current = values.firstIndex(where: { $0 == filter }) ?? 0
    filter = values[(current + 1) % values.count]
  }

  func extractText(_ entry: ClipboardEntry) {
    guard entry.kind == .image, let url = entry.dragURLs.first else { return }
    Task {
      guard let text = await TextRecognition.recognizeText(in: url) else {
        Toaster.shared.tip("clipboard-ocr-empty", "No readable text was found in that image.")
        return
      }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
      Toaster.shared.copied("Extracted text")
    }
  }

  func shortenAndCopy(_ url: URL) {
    Task { await shortenAndCopy(url, using: { try await LinkShortener.shorten($0) }) }
  }

  func shortenAndCopy(_ url: URL, using shorten: @escaping (URL) async throws -> URL,
                      pasteboard board: NSPasteboard = .general) async {
    do {
      let shortened = try await shorten(url)
      board.clearContents()
      board.setString(shortened.absoluteString, forType: .string)
      if board === NSPasteboard.general { changeCount = board.changeCount }
      record(ClipboardEntry(kind: .text, text: shortened.absoluteString, title: shortened.absoluteString,
        detail: "Shortened link · da.gd"))
      Toaster.shared.copied("Short link")
    } catch {
      Toaster.shared.note(error.localizedDescription)
    }
  }

  private func poll() {
    let board = NSPasteboard.general
    guard board.changeCount != changeCount else { return }
    changeCount = board.changeCount
    capture(board)
  }

  func capture(_ board: NSPasteboard) {
    let excluded = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
      "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword"]
    guard captureEnabled, !excluded.contains(where: { board.types?.contains(.init($0)) == true }) else { return }
    if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
      !urls.isEmpty {
      record(ClipboardEntry(kind: .file, paths: urls.map(\.path), title: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files",
        detail: urls.map(\.pathExtension).filter { !$0.isEmpty }.joined(separator: ", ")))
      return
    }
    if let image = NSImage(pasteboard: board), let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
      do {
        let folder = StoragePaths.received.appendingPathComponent("Clipboard", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(UUID().uuidString + ".png")
        try png.write(to: url, options: .atomic)
        record(ClipboardEntry(kind: .image, paths: [url.path], title: "Copied image",
          detail: "\(Int(image.size.width)) × \(Int(image.size.height))"))
      } catch { }
      return
    }
    if let text = board.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
      let title = text.replacingOccurrences(of: "\n", with: " ")
      record(ClipboardEntry(kind: .text, text: text, title: String(title.prefix(70)),
        detail: "\(text.count) character\(text.count == 1 ? "" : "s")"))
    }
  }

  private func record(_ entry: ClipboardEntry) {
    let duplicate = entries.first.map { $0.kind == entry.kind && $0.text == entry.text && $0.paths == entry.paths } ?? false
    guard captureEnabled, !duplicate else { return }
    entries.insert(entry, at: 0)
    if entries.count > 200 { entries.removeLast(entries.count - 200) }
    save()
  }

  private func load() {
    guard let data = try? Data(contentsOf: historyURL), let value = try? JSONDecoder().decode([ClipboardEntry].self, from: data) else { return }
    entries = value
  }
  private func save() {
    guard persistsHistory else { return }
    guard let data = try? JSONEncoder().encode(entries) else { return }
    try? data.write(to: historyURL, options: .atomic)
  }
}

private final class ClipboardHostingView: NSHostingView<AnyView> {
  var hover: (Bool) -> Void = { _ in }
  var keyHandler: (NSEvent) -> Bool = { _ in false }
  private var area: NSTrackingArea?
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let area { removeTrackingArea(area) }
    let next = NSTrackingArea(rect: .zero,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
    addTrackingArea(next); area = next
  }
  override func mouseEntered(with event: NSEvent) { hover(true) }
  override func mouseExited(with event: NSEvent) { hover(false) }
  override func mouseDown(with event: NSEvent) { hover(true); super.mouseDown(with: event) }
  override func rightMouseDown(with event: NSEvent) { hover(true); super.rightMouseDown(with: event) }
  override func scrollWheel(with event: NSEvent) { hover(true); super.scrollWheel(with: event) }
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func keyDown(with event: NSEvent) {
    if !keyHandler(event) { super.keyDown(with: event) }
  }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    keyHandler(event) || super.performKeyEquivalent(with: event)
  }
}

private struct ClipboardShelfView: View {
  @ObservedObject var history = ClipboardHistoryStore.shared
  @ObservedObject var shortcuts = CourierShortcutStore.shared
  @FocusState private var searchFocused: Bool
  var skin: ParcelSkin
  var close: () -> Void
  var addToParcel: (ClipboardEntry) -> Void
  var processImage: (ClipboardEntry) -> Void
  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 4) {
        Label("Clipboard", systemImage: "list.clipboard").font(.system(size: 12, weight: .semibold))
          .lineLimit(1).layoutPriority(1)
        Spacer(minLength: 6)
        Text(shortcuts.binding(for: .clipboard).displayName).font(.system(size: 9))
          .foregroundStyle(skin.palette.secondary).fixedSize()
        Menu {
          Button("All") { history.filter = nil }
          ForEach(ClipboardEntryKind.allCases) { kind in Button(kind.label) { history.filter = kind } }
        } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
          .menuStyle(.borderlessButton).frame(width: 26, height: 26).contentShape(Rectangle())
        Button(action: close) { Image(systemName: "xmark").frame(width: 26, height: 26) }
          .buttonStyle(.plain).contentShape(Rectangle())
      }
      .frame(height: 26)
      TextField("Search text, images, files, today…", text: $history.search)
        .textFieldStyle(.roundedBorder).font(.system(size: 10)).focused($searchFocused)
      List {
        ForEach(history.filtered) { entry in
          ClipboardHistoryRow(entry: entry, history: history, skin: skin, addToParcel: addToParcel, processImage: processImage)
            .listRowSeparator(.hidden)
        }
        if history.filtered.isEmpty {
          Text("Nothing copied yet.").font(.system(size: 10)).padding(24).frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
        }
      }
      .listStyle(.plain).scrollContentBackground(.hidden).scrollIndicators(.visible)
    }.padding(10).foregroundStyle(skin.palette.text)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
      .onReceive(NotificationCenter.default.publisher(for: .parcelFocusClipboardSearch)) { _ in searchFocused = true }
  }

}

struct ClipboardHistoryRow: View {
  let entry: ClipboardEntry
  @ObservedObject var history: ClipboardHistoryStore
  let skin: ParcelSkin
  var addToParcel: (ClipboardEntry) -> Void
  var processImage: (ClipboardEntry) -> Void
  private var colour: Color? {
    guard let text = entry.text?.trimmingCharacters(in: .whitespacesAndNewlines), text.hasPrefix("#") else { return nil }
    let digits = text.dropFirst()
    guard digits.count == 3 || digits.count == 6 else { return nil }
    let redGreenBlue = digits.count == 3 ? digits.map { String(repeating: String($0), count: 2) }.joined() : String(digits)
    guard let value = UInt32(redGreenBlue, radix: 16) else { return nil }
    return Color(red: Double(value >> 16) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
  }
  var body: some View {
    HStack(spacing: 8) {
      ZStack {
        if let colour {
          RoundedRectangle(cornerRadius: 4).fill(colour).overlay {
            RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.25))
          }.frame(width: 20, height: 20).accessibilityLabel("Colour swatch")
        } else {
          Image(systemName: entry.kind.symbol).frame(width: 22).foregroundStyle(skin.palette.accent)
        }
        FileDropSurface(enabled: true, outgoing: entry.dragURLs, outgoingText: entry.dragText,
          tap: { history.copy(entry) }, receive: { _ in }, receiving: { _ in }, hover: { _ in },
          failure: { _ in }, courierMenu: { _ in menu(for: entry) })
      }
      .frame(width: 22, height: 32).help("Drag this item")
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.title).font(.system(size: 10, weight: .medium)).lineLimit(2)
        Text(entry.detail).font(.system(size: 8)).foregroundStyle(skin.palette.secondary).lineLimit(1)
      }
      .contentShape(Rectangle()).onTapGesture { history.copy(entry) }
      Spacer(minLength: 0)
      Button { history.copy(entry) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain)
        .accessibilityLabel("Copy " + entry.title)
      Button { history.remove(entry.id) } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        .accessibilityLabel("Remove " + entry.title)
    }
    .padding(8).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
    .listRowBackground(Color.clear)
  }

  private func menu(for entry: ClipboardEntry) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.addItem(CourierMenuAction("Copy", action: { history.copy(entry) }))
    menu.addItem(CourierMenuAction("Add to current parcel", action: { addToParcel(entry) }))
    if entry.linkURLs.count == 1, let url = entry.linkURLs.first {
      menu.addItem(CourierMenuAction("Shorten and copy link", action: { history.shortenAndCopy(url) }))
    } else if !entry.linkURLs.isEmpty {
      let item = NSMenuItem(title: "Shorten and copy link", action: nil, keyEquivalent: "")
      let links = NSMenu()
      for url in entry.linkURLs {
        links.addItem(CourierMenuAction(url.host ?? url.absoluteString, action: { history.shortenAndCopy(url) }))
      }
      item.submenu = links
      menu.addItem(item)
    }
    if entry.kind == .image {
      menu.addItem(CourierMenuAction("Process image…", action: { processImage(entry) }))
      menu.addItem(CourierMenuAction("Copy text with OCR", action: { history.extractText(entry) }))
    }
    menu.addItem(.separator())
    menu.addItem(CourierMenuAction("Remove from clipboard history", action: { history.remove(entry.id) }))
    return menu
  }
}

@MainActor final class CourierClipboardController {
  private(set) var panel: ShelfPanel?
  func show(parent: NSPanel, skin: ParcelSkin, hover: @escaping (Bool) -> Void, close: @escaping () -> Void,
            addToParcel: @escaping (ClipboardEntry) -> Void, processImage: @escaping (ClipboardEntry) -> Void,
            keyHandler: @escaping (NSEvent) -> Bool) {
    guard let screen = parent.screen?.visibleFrame else { return }
    let size = CGSize(width: 260, height: min(420, screen.height - 24))
    let x = max(screen.minX + 8, parent.frame.minX - size.width - 16)
    let y = min(max(parent.frame.maxY - size.height, screen.minY + 8), screen.maxY - size.height - 8)
    let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
    let window = panel ?? ShelfPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.level = .popUpMenu; window.isFloatingPanel = true; window.hidesOnDeactivate = false
    window.isReleasedWhenClosed = false; window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = true
    window.ignoresMouseEvents = false; window.acceptsMouseMovedEvents = true; window.becomesKeyOnlyIfNeeded = false
    let host = ClipboardHostingView(rootView: AnyView(ClipboardShelfView(history: .shared, skin: skin,
      close: close, addToParcel: addToParcel, processImage: processImage)))
    host.sizingOptions = []; host.hover = hover; host.keyHandler = keyHandler
    window.contentView = host; window.setFrame(frame, display: true)
    if window.parent !== parent { window.parent?.removeChildWindow(window); parent.addChildWindow(window, ordered: .above) }
    panel = window
    NSApp.setActivationPolicy(.regular)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  func hide() {
    guard let panel else { return }
    panel.parent?.removeChildWindow(panel); panel.orderOut(nil); panel.contentView = nil
    AppController.shared.restoreAccessoryPolicyIfPossible()
  }
}

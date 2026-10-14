import AppKit
import Combine
import Foundation

/// Clipboard history with privacy guardrails, inspired by DropKit and Unclutter.
/// Watches the general pasteboard, keeps recent text and image clips, and lets
/// the user pin, search, and re-copy them. Sensitive content is never stored:
/// password-manager apps are skipped and concealed pasteboard types are ignored.
@MainActor
final class ClipboardHistory: ObservableObject {
  struct Entry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var capturedAt: Date = Date()
    var text: String?
    /// PNG data for image clips (thumbnail-scale).
    var imagePNG: Data?
    var isPinned: Bool = false
    var preview: String {
      if let text, !text.isEmpty { return String(text.prefix(120)) }
      return "Image"
    }
  }

  static let shared = ClipboardHistory()

  @Published private(set) var entries: [Entry] = []
  @Published var isEnabled = UserDefaults.standard.object(forKey: "parcel-clipboard-watch") as? Bool ?? false {
    didSet { UserDefaults.standard.set(isEnabled, forKey: "parcel-clipboard-watch") }
  }

  private var timer: Timer?
  private var lastChangeCount: Int = -1
  private let maxEntries = 50

  /// Bundle IDs whose clipboard content is never captured.
  private let sensitiveApps: Set<String> = [
    "com.agilebits.onepassword7", "com.agilebits.onepassword8",
    "com.bitwarden.desktop", "com.dashlane.dashlane",
    "com.lastpass.lastpass", "com.1password.1password",
    "org.keepassxc.keepassxc",
  ]

  private init() { load() }

  func start() {
    stop()
    timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.poll() }
    }
  }

  func stop() { timer?.invalidate(); timer = nil }

  private func poll() {
    guard isEnabled else { return }
    let pb = NSPasteboard.general
    guard pb.changeCount != lastChangeCount else { return }
    lastChangeCount = pb.changeCount
    if isSensitiveContext() { return }
    capture(from: pb)
  }

  /// True when the frontmost app is a password manager or the pasteboard
  /// carries a concealed/private type.
  private func isSensitiveContext() -> Bool {
    if let app = NSWorkspace.shared.frontmostApplication,
      sensitiveApps.contains(app.bundleIdentifier ?? "")
    { return true }
    let concealed = NSPasteboard.general.types?.contains(where: {
      $0.rawValue.lowercased().contains("concealed")
        || $0.rawValue.lowercased().contains("transient")
        || $0.rawValue == "org.nspasteboard.auto-generated-type"
    }) ?? false
    return concealed
  }

  private func capture(from pb: NSPasteboard) {
    if let text = pb.string(forType: .string), !text.isEmpty {
      // Skip if the most recent entry already holds this text.
      if entries.first?.text == text { return }
      push(Entry(text: text))
      return
    }
    if let image = NSImage(pasteboard: pb) {
      push(Entry(imagePNG: thumbnailPNG(image)))
    }
  }

  private func thumbnailPNG(_ image: NSImage) -> Data? {
    let maxSide: CGFloat = 320
    let ratio = min(1, maxSide / max(image.size.width, image.size.height))
    let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
    let thumb = NSImage(size: size)
    thumb.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: size))
    thumb.unlockFocus()
    guard let tiff = thumb.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff)
    else { return nil }
    return rep.representation(using: .png, properties: [:])
  }

  private func push(_ entry: Entry) {
    entries.removeAll { $0.text == entry.text && $0.imagePNG == entry.imagePNG }
    entries.insert(entry, at: 0)
    // Pinned entries never expire; unpinned ones roll off the end.
    let pinned = entries.filter(\.isPinned)
    let unpinned = entries.filter { !$0.isPinned }.prefix(maxEntries - pinned.count)
    entries = (pinned + unpinned).sorted { $0.capturedAt > $1.capturedAt }
    save()
  }

  func copy(_ entry: Entry) {
    let pb = NSPasteboard.general
    pb.clearContents()
    if let text = entry.text { pb.setString(text, forType: .string) }
    else if let data = entry.imagePNG, let image = NSImage(data: data) {
      pb.writeObjects([image])
    }
    lastChangeCount = pb.changeCount
  }

  func togglePin(_ id: UUID) {
    guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
    entries[i].isPinned.toggle()
    save()
  }

  func remove(_ id: UUID) {
    entries.removeAll { $0.id == id }
    save()
  }

  func clearUnpinned() {
    entries.removeAll { !$0.isPinned }
    save()
  }

  // MARK: - Persistence

  private var storeURL: URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first!.appendingPathComponent("Parcel", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("clipboard-history.json")
  }

  private func save() {
    if let data = try? JSONEncoder().encode(entries) {
      try? data.write(to: storeURL, options: .atomic)
    }
  }

  private func load() {
    guard let data = try? Data(contentsOf: storeURL),
      let decoded = try? JSONDecoder().decode([Entry].self, from: data)
    else { return }
    entries = decoded
  }
}

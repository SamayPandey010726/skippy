import AppKit
import AVFoundation
import CoreImage.CIFilterBuiltins
import EventKit
import PDFKit
import ParcelCore
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

extension Notification.Name {
  static let parcelsNextWidgetPage = Notification.Name("parcels-next-widget-page")
  static let parcelsPreviousWidgetPage = Notification.Name("parcels-previous-widget-page")
}

enum NotchModule: String, CaseIterable, Identifiable {
  case dashboard, parcel, clipboard, extract, color, timer, notes, qr, search, launcher, music, downloads, awake, recent, system, calendar, calculator, screenshot, draw, convert, compress, extractArchive
  var id: String { rawValue }
  var title: String {
    switch self {
    case .dashboard: "Skippy"
    case .parcel: "File Shelf"
    case .clipboard: "Clipboard"
    case .extract: "Extract text"
    case .color: "Pick colour"
    case .timer: "Timer"
    case .notes: "Notes"
    case .qr: "QR tools"
    case .search: "Search"
    case .launcher: "Apps"
    case .music: "Music"
    case .downloads: "Downloads"
    case .awake: "Stay awake"
    case .recent: "Recent actions"
    case .system: "Mac"
    case .calendar: "Calendar"
    case .calculator: "Calculator"
    case .screenshot: "Screenshots"
    case .draw: "Draw on screen"
    case .convert: "Convert files"
    case .compress: "Compress files"
    case .extractArchive: "Extract archive"
    }
  }
  var symbol: String {
    switch self {
    case .dashboard: "square.grid.2x2.fill"
    case .parcel: "shippingbox.fill"
    case .clipboard: "list.clipboard"
    case .extract: "text.viewfinder"
    case .color: "eyedropper.halffull"
    case .timer: "timer"
    case .notes: "note.text"
    case .qr: "qrcode.viewfinder"
    case .search: "magnifyingglass"
    case .launcher: "square.grid.2x2"
    case .music: "waveform"
    case .downloads: "arrow.down.circle"
    case .awake: "cup.and.saucer.fill"
    case .recent: "clock.arrow.circlepath"
    case .system: "gauge.with.dots.needle.67percent"
    case .calendar: "calendar"
    case .calculator: "plus.forwardslash.minus"
    case .screenshot: "rectangle.dashed.badge.record"
    case .draw: "pencil.tip.crop.circle"
    case .convert: "arrow.trianglehead.clockwise"
    case .compress: "archivebox"
    case .extractArchive: "shippingbox.and.arrow.backward"
    }
  }
}

struct PinnedNotchApp: Codable, Identifiable, Equatable {
  var bundleIdentifier: String
  var name: String
  var id: String { bundleIdentifier }
}

struct NotchMacro: Codable, Identifiable {
  var id = UUID()
  var name: String
  var command: String
}

@MainActor final class NotchToolStore: NSObject, ObservableObject, AVAudioPlayerDelegate {
  enum MediaAction { case previous, toggle, next }
  static let shared = NotchToolStore()
  @Published var note: String { didSet { defaults.set(note, forKey: "parcel.notch.note") } }
  @Published var timerMinutes = 25
  @Published var keepAwakeDuringTimer = false
  @Published private(set) var timerEnd: Date?
  @Published private(set) var remaining: TimeInterval = 0
  @Published private(set) var ocrText = ""
  @Published private(set) var qrText = ""
  @Published private(set) var pickedColour = "#5B8C6A"
  @Published private(set) var audioTitle = "Choose an audio file"
  @Published private(set) var isPlaying = false
  @Published private(set) var mediaTitle = "Nothing playing"
  @Published private(set) var mediaArtist = "Music and Spotify appear here"
  @Published private(set) var mediaSource: String?
  @Published private(set) var mediaIsPlaying = false
  @Published private(set) var downloads: [URL] = []
  @Published private(set) var isKeepingAwake = false
  @Published private(set) var pinnedApps: [PinnedNotchApp] {
    didSet {
      if let data = try? JSONEncoder().encode(pinnedApps) { defaults.set(data, forKey: "parcel.notch.pinnedApps.v1") }
    }
  }
  @Published private(set) var status = "Ready"
  @Published private(set) var calendarEvents: [EKEvent] = []
  @Published private(set) var calendarMessage = "Connect Calendar to see upcoming events."
  @Published private(set) var captures: [NSImage] = []
  @Published var captureColumns = 1
  @Published private(set) var macros: [NotchMacro] {
    didSet { if let data = try? JSONEncoder().encode(macros) { defaults.set(data, forKey: "parcels.macros.v1") } }
  }
  @Published private(set) var intelligenceResult = ""
  @Published private(set) var intelligenceWorking = false
  private let defaults: UserDefaults
  private var clock: Timer?
  private var player: AVAudioPlayer?
  private var mediaRefreshInFlight = false
  private var caffeinate: Process?
  private var timerEnabledAwake = false
  private let eventStore = EKEventStore()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    note = defaults.string(forKey: "parcel.notch.note") ?? ""
    pinnedApps = defaults.data(forKey: "parcel.notch.pinnedApps.v1")
      .flatMap { try? JSONDecoder().decode([PinnedNotchApp].self, from: $0) } ?? []
    macros = defaults.data(forKey: "parcels.macros.v1")
      .flatMap { try? JSONDecoder().decode([NotchMacro].self, from: $0) } ?? [
        NotchMacro(name: "Open Downloads", command: "open ~/Downloads"),
        NotchMacro(name: "Open Calculator", command: "open -a Calculator")
      ]
    super.init()
  }

  func startTimer() {
    if keepAwakeDuringTimer && !isKeepingAwake {
      toggleStayAwake()
      timerEnabledAwake = isKeepingAwake
    }
    let seconds = TimeInterval(max(1, min(180, timerMinutes)) * 60)
    timerEnd = Date().addingTimeInterval(seconds)
    remaining = seconds
    clock?.invalidate()
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    clock = timer
    requestNotificationPermission()
    status = "Timer started"
  }

  func stopTimer() {
    clock?.invalidate(); clock = nil; timerEnd = nil; remaining = 0
    if timerEnabledAwake && isKeepingAwake { toggleStayAwake() }
    timerEnabledAwake = false
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["parcel-notch-timer"])
    status = "Timer stopped"
  }

  private func tick() {
    guard let end = timerEnd else { return }
    remaining = max(0, end.timeIntervalSinceNow)
    guard remaining == 0 else { return }
    clock?.invalidate(); clock = nil; timerEnd = nil
    if timerEnabledAwake && isKeepingAwake { toggleStayAwake() }
    timerEnabledAwake = false
    NSSound(named: "Glass")?.play()
    Toaster.shared.note("Timer finished")
    status = "Timer finished"
  }

  private func requestNotificationPermission() {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
      guard granted else { return }
      Task { @MainActor in self?.scheduleTimerNotification() }
    }
  }

  private func scheduleTimerNotification() {
    guard let end = timerEnd else { return }
    let content = UNMutableNotificationContent()
    content.title = "Skippy timer"
    content.body = "Time is up."
    content.sound = .default
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["parcel-notch-timer"])
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "parcel-notch-timer", content: content, trigger: trigger))
  }

  func pickColour() {
    let restore = DropPopupController.shared.beginScreenSelection()
    NSColorSampler().show { [weak self] colour in
      Task { @MainActor in
        defer { restore() }
        guard let colour, let hex = Self.hexValue(for: colour) else { return }
        self?.pickedColour = hex
        self?.copyText(hex, label: "Colour")
      }
    }
  }

  nonisolated static func hexValue(for colour: NSColor) -> String? {
    guard let rgb = colour.usingColorSpace(.sRGB) else { return nil }
    func byte(_ fraction: CGFloat) -> Int { Int((min(1, max(0, fraction)) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
  }

  func extractFromClipboard() {
    guard let image = NSImage(pasteboard: .general), let data = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: data), let cg = rep.cgImage else {
      status = "Copy an image first"; return
    }
    Task { await recognize(cg) }
  }

  func extractFromScreen() {
    captureScreenArea { [weak self] url in
      Task { @MainActor in
        defer { try? FileManager.default.removeItem(at: url) }
        guard let self else { return }
        if let text = await TextRecognition.recognizeText(in: url) { self.publishOCR(text) }
        else { self.status = "No readable text found" }
      }
    }
  }

  func connectCalendar() {
    Task {
      do {
        guard try await eventStore.requestFullAccessToEvents() else {
          calendarMessage = "Calendar access is off. Allow it in System Settings."
          return
        }
        refreshCalendar()
      } catch { calendarMessage = "Could not access Calendar: \(error.localizedDescription)" }
    }
  }

  func refreshCalendar() {
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
      calendarMessage = "Connect Calendar to see upcoming events."
      return
    }
    let start = Date()
    guard let end = Calendar.current.date(byAdding: .day, value: 14, to: start) else { return }
    let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
    calendarEvents = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    calendarMessage = calendarEvents.isEmpty ? "No upcoming events in the next two weeks." : "Upcoming events"
  }

  func captureAnother() {
    captureScreenArea { [weak self] url in
      defer { try? FileManager.default.removeItem(at: url) }
      self?.addCapture(from: url)
    }
  }

  func addCapture(from url: URL) {
    guard let data = try? Data(contentsOf: url), let image = NSImage(data: data), image.isValid else {
      status = "Could not read the screenshot"; return
    }
    captures.append(image)
    status = "Screenshot added"
  }

  func captureForLens() {
    captureScreenArea { [weak self] url in
      defer { try? FileManager.default.removeItem(at: url) }
      guard let data = try? Data(contentsOf: url), let image = NSImage(data: data), image.isValid else {
        self?.status = "Could not read the screenshot"; return
      }
      NSPasteboard.general.clearContents()
      guard NSPasteboard.general.writeObjects([image]), let address = URL(string: "https://lens.google.com/") else {
        self?.status = "Could not copy the screenshot"; return
      }
      NSWorkspace.shared.open(address)
      self?.status = "Screenshot copied. Paste it into Google Lens."
    }
  }

  func clearCaptures() { captures.removeAll() }

  func captureWorkspace(_ mode: WorkspaceCaptureMode) {
    ScreenCaptureWorkspace.shared.capture(mode) { [weak self] result in self?.acceptCaptures(result) }
  }

  func acceptCaptures(_ result: Result<[CGImage], Error>) {
    switch result {
    case .success(let images):
      guard !images.isEmpty else { return }
      captures.append(contentsOf: images.map { NSImage(cgImage: $0, size: .zero) })
      status = images.count == 1 ? "Screenshot added" : "\(images.count) screenshots added"
    case .failure(let error): status = error.localizedDescription
    }
  }

  func moveCapture(_ index: Int, by step: Int) {
    guard captures.indices.contains(index), captures.indices.contains(index + step) else { return }
    captures.swapAt(index, index + step)
  }

  func removeCapture(_ index: Int) {
    if captures.indices.contains(index) { captures.remove(at: index) }
  }

  private func combinedCapturePNG() -> Data? {
    let images = captures.compactMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    guard images.count == captures.count, !images.isEmpty,
      let combined = CaptureComposition.combine(images, columns: captureColumns) else {
      status = "No combined image. Reduce the number or size of the selections."
      return nil
    }
    return NSBitmapImageRep(cgImage: combined).representation(using: .png, properties: [:])
  }

  func copyCombinedCaptures() {
    guard let png = combinedCapturePNG() else { return }
    NSPasteboard.general.clearContents()
    status = NSPasteboard.general.setData(png, forType: .png) ? "Combined image copied" : "Could not copy the image"
  }

  func saveCombinedCaptures() {
    guard let png = combinedCapturePNG() else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = "Skippy capture.png"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try png.write(to: url, options: .atomic); status = "Combined image saved" }
    catch { status = error.localizedDescription }
  }

  private func captureScreenArea(_ completion: @escaping (URL) -> Void) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("parcels-capture-\(UUID().uuidString).png")
    let restore = DropPopupController.shared.beginScreenSelection()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-i", "-x", url.path]
    process.terminationHandler = { [weak self] process in
      DispatchQueue.main.async {
        restore()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) else {
          try? FileManager.default.removeItem(at: url)
          self?.status = "Screen selection cancelled or unavailable"
          return
        }
        completion(url)
      }
    }
    do { try process.run() }
    catch { restore(); status = "Could not start screen capture" }
  }

  func chooseImageForOCR() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image, .pdf]
    panel.allowsMultipleSelection = false
    panel.message = "Choose an image or PDF page to read"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    Task {
      if url.pathExtension.lowercased() == "pdf",
        let image = NSImage(contentsOf: url), let data = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: data), let cg = rep.cgImage { await recognize(cg) }
      else if let text = await TextRecognition.recognizeText(in: url) { publishOCR(text) }
      else { status = "No readable text found" }
    }
  }

  private func recognize(_ image: CGImage) async {
    if let text = await TextRecognition.recognizeText(in: image) { publishOCR(text) }
    else { status = "No readable text found" }
  }

  private func publishOCR(_ text: String) {
    ocrText = text
    copyText(text, label: "Extracted text")
    status = "Text copied"
  }

  func generateQR(_ value: String) -> NSImage? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(trimmed.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage?.transformed(by: .init(scaleX: 8, y: 8)) else { return nil }
    let rep = NSCIImageRep(ciImage: output)
    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
  }

  func copyQR(_ value: String) {
    guard let image = generateQR(value) else { status = "Enter text or a link"; return }
    NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image])
    status = "QR code copied"
  }

  func scanQR() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.message = "Choose an image containing a QR code"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    readQR(at: url)
  }

  func scanScreenQR() {
    captureScreenArea { [weak self] url in
      defer { try? FileManager.default.removeItem(at: url) }
      self?.readQR(at: url)
    }
  }

  func scanClipboardQR() {
    guard let image = NSImage(pasteboard: .general), let data = image.tiffRepresentation else {
      status = "Copy an image containing a QR code first"; return
    }
    readQR(using: VNImageRequestHandler(data: data))
  }

  private func readQR(at url: URL) { readQR(using: VNImageRequestHandler(url: url)) }

  private func readQR(using handler: VNImageRequestHandler) {
    let request = VNDetectBarcodesRequest { [weak self] request, _ in
      let value = (request.results as? [VNBarcodeObservation])?.first?.payloadStringValue
      Task { @MainActor in
        guard let value else { self?.status = "No QR code found"; return }
        self?.qrText = value
        self?.copyText(value, label: "QR result")
      }
    }
    request.symbologies = [.qr]
    do { try handler.perform([request]) }
    catch { status = "Could not read that image" }
  }

  func searchGoogle(_ query: String) {
    guard let url = Self.searchURL(for: query),
          let browser = NSWorkspace.shared.urlForApplication(toOpen: url) else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.open([url], withApplicationAt: browser, configuration: configuration) { app, error in
      Task { @MainActor in
        if let error { self.status = error.localizedDescription; return }
        let shelf = DropPopupController.shared
        if shelf.activeModule == .search { shelf.dismiss() }
        app?.activate(options: [.activateIgnoringOtherApps])
      }
    }
  }

  static func searchURL(for query: String) -> URL? {
    let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    var components = URLComponents(string: "https://www.google.com/search")!
    components.queryItems = [URLQueryItem(name: "q", value: value)]
    components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    return components.url
  }

  func addMacro(name: String, command: String) {
    let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let script = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, !script.isEmpty else { status = "Enter a name and command"; return }
    macros.append(NotchMacro(name: title, command: script))
    status = "Command saved"
  }

  func removeMacro(_ macro: NotchMacro) { macros.removeAll { $0.id == macro.id } }

  func runMacro(_ macro: NotchMacro) {
    let alert = NSAlert()
    alert.messageText = "Run \(macro.name)?"
    alert.informativeText = "This runs the following command with your account permissions:\n\n\(macro.command)"
    alert.addButton(withTitle: "Run")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", macro.command]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.terminationHandler = { [weak self] process in
      DispatchQueue.main.async {
        self?.status = process.terminationStatus == 0 ? "Command finished" : "Command failed (\(process.terminationStatus))"
      }
    }
    do { try process.run(); status = "Running \(macro.name)…" }
    catch { status = "Could not start command" }
  }

  var launchableApps: [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
      .reduce(into: [String: NSRunningApplication]()) { result, app in
        result[app.bundleIdentifier ?? app.localizedName ?? UUID().uuidString] = app
      }.values.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
  }

  func activate(_ app: NSRunningApplication) {
    app.activate(options: [])
  }

  func togglePinned(_ app: NSRunningApplication) {
    guard let bundleIdentifier = app.bundleIdentifier else { return }
    if let index = pinnedApps.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) {
      pinnedApps.remove(at: index)
    } else {
      pinnedApps.append(PinnedNotchApp(bundleIdentifier: bundleIdentifier,
        name: app.localizedName ?? "App"))
    }
  }

  func choosePinnedApp() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.applicationBundle]
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    panel.message = "Choose an app to pin to Skippy"
    guard panel.runModal() == .OK, let url = panel.url,
      let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
    guard !pinnedApps.contains(where: { $0.bundleIdentifier == id }) else { status = "App is already pinned"; return }
    pinnedApps.append(PinnedNotchApp(bundleIdentifier: id, name: url.deletingPathExtension().lastPathComponent))
    status = "App pinned"
  }

  func unpinApp(_ app: PinnedNotchApp) { pinnedApps.removeAll { $0.id == app.id } }

  func isPinned(_ app: NSRunningApplication) -> Bool {
    guard let id = app.bundleIdentifier else { return false }
    return pinnedApps.contains { $0.bundleIdentifier == id }
  }

  func icon(for app: PinnedNotchApp) -> NSImage {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) else { return NSImage() }
    return NSWorkspace.shared.icon(forFile: url.path)
  }

  func launch(_ app: PinnedNotchApp) {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) else {
      status = "\(app.name) is no longer installed"; return
    }
    NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] _, error in
      if let error { Task { @MainActor in self?.status = "Could not open \(app.name): \(error.localizedDescription)" } }
    }
  }

  func refreshDownloads() async {
    guard let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
    let files = await Task.detached(priority: .utility) { Self.recentDownloads(in: folder) }.value
    if !Task.isCancelled { downloads = files }
  }

  nonisolated static func recentDownloads(in folder: URL) -> [URL] {
    let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey]
    let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys),
                                                              options: [.skipsHiddenFiles])) ?? []
    let dated: [(URL, Date)] = urls.compactMap { url in
      guard let info = try? url.resourceValues(forKeys: keys), info.isDirectory == false else { return nil }
      return (url, info.contentModificationDate ?? .distantPast)
    }
    return dated.sorted { $0.1 > $1.1 }.prefix(12).map { $0.0 }
  }

  func openDownloads() {
    guard let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
    NSWorkspace.shared.open(folder)
  }

  func toggleStayAwake() {
    if let caffeinate {
      caffeinate.terminate(); self.caffeinate = nil; isKeepingAwake = false; status = "Normal sleep restored"
      return
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
    process.arguments = ["-dimsu"]
    do {
      try process.run(); caffeinate = process; isKeepingAwake = true; status = "Mac will stay awake"
    } catch { status = "Stay Awake could not start" }
  }

  func chooseAudio() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.audio]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    playAudio(at: url)
  }

  func playAudio(at url: URL) {
    do {
      let opened = try AVAudioPlayer(contentsOf: url)
      player = opened
      player?.delegate = self
      audioTitle = url.deletingPathExtension().lastPathComponent
      isPlaying = opened.play(); status = isPlaying ? "Playing" : "Audio output unavailable"
      if mediaSource == nil { mediaTitle = audioTitle; mediaArtist = "Local audio" }
    } catch { status = "That audio file could not be played" }
  }

  func toggleAudio() {
    guard let player else { chooseAudio(); return }
    if player.isPlaying { player.pause(); isPlaying = false; status = "Paused" }
    else { isPlaying = player.play(); status = isPlaying ? "Playing" : "Audio output unavailable" }
  }

  /// Music and Spotify expose stable AppleScript dictionaries; this avoids private MediaRemote APIs.
  func refreshMedia() {
    guard !mediaRefreshInFlight else { return }
    let running = [("com.apple.Music", "Music"), ("com.spotify.client", "Spotify")]
      .filter { NSRunningApplication.runningApplications(withBundleIdentifier: $0.0).first != nil }
      .map(\.1)
    mediaRefreshInFlight = true
    Task {
      let snapshot = await Task.detached(priority: .utility) { Self.readMedia(from: running) }.value
      mediaRefreshInFlight = false
      if let snapshot {
        mediaIsPlaying = snapshot.playing; mediaTitle = snapshot.title
        mediaArtist = snapshot.artist; mediaSource = snapshot.source
      } else {
        mediaSource = nil; mediaIsPlaying = false
        mediaTitle = player == nil ? "Nothing playing" : audioTitle
        mediaArtist = player == nil ? "Music and Spotify appear here" : "Playing in Skippy"
      }
    }
  }

  func controlMedia(_ action: MediaAction) {
    guard let source = mediaSource else { toggleAudio(); refreshMedia(); return }
    let command: String
    switch action {
    case .previous: command = "previous track"
    case .toggle: command = "playpause"
    case .next: command = "next track"
    }
    status = "Sending to \(source)…"
    Task {
      let succeeded = await Task.detached(priority: .userInitiated) {
        Self.runAppleScript("tell application \"\(source)\" to \(command)", timeout: 1) != nil
      }.value
      status = succeeded ? (action == .toggle ? "Playback changed" : "Track changed")
        : "\(source) did not accept that control"
      refreshMedia()
    }
  }

  private nonisolated static func readMedia(from applications: [String]) ->
    (source: String, playing: Bool, title: String, artist: String)? {
    for application in applications {
      let script = """
      tell application "\(application)" to set bits to {(player state as text), name of current track, artist of current track}
      set AppleScript's text item delimiters to ASCII character 31
      return bits as text
      """
      guard let output = runAppleScript(script, timeout: 0.7) else { continue }
      let values = output.components(separatedBy: "\u{1F}")
      guard values.count == 3 else { continue }
      return (application, values[0].lowercased() == "playing",
        values[1].isEmpty ? "Unknown track" : values[1], values[2].isEmpty ? application : values[2])
    }
    return nil
  }

  private nonisolated static func runAppleScript(_ source: String, timeout: TimeInterval) -> String? {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", source]
    process.standardOutput = output
    process.standardError = Pipe()
    do { try process.run() } catch { return nil }
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    guard !process.isRunning else { process.terminate(); return nil }
    guard process.terminationStatus == 0 else { return nil }
    return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in self.isPlaying = false; self.status = "Finished" }
  }

  func copyText(_ value: String, label: String) {
    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
    Toaster.shared.copied(label)
  }

  func summarizeWithAppleIntelligence(_ text: String) {
    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty else { status = "Add some text first"; return }
    #if canImport(FoundationModels)
    guard #available(macOS 26.0, *) else { status = "Apple Intelligence needs macOS 26 or later"; return }
    guard SystemLanguageModel.default.isAvailable else { status = "Apple Intelligence is not available on this Mac"; return }
    intelligenceWorking = true
    status = "Summarising on this Mac…"
    Task {
      do {
        let session = LanguageModelSession(model: SystemLanguageModel.default,
          instructions: "Summarize user-provided text clearly and briefly. Do not invent facts.")
        let response = try await session.respond(to: "Summarize this in at most five bullets:\n\n\(String(input.prefix(12_000)))")
        intelligenceResult = response.content
        status = "Summary ready"
      } catch { status = "Apple Intelligence could not finish: \(error.localizedDescription)" }
      intelligenceWorking = false
    }
    #else
    status = "Apple Intelligence is unavailable in this build"
    #endif
  }
}

struct NotchToolsView: View {
  @ObservedObject var shelf: DropPopupController
  @ObservedObject private var tools = NotchToolStore.shared
  @ObservedObject private var widgets = NotchWidgetStore.shared
  @ObservedObject private var clipboard = ClipboardHistoryStore.shared
  @ObservedObject private var recent = RecentActionStore.shared
  @EnvironmentObject private var store: ParcelStore
  var skin: ParcelSkin
  @ObservedObject private var shortcuts = CourierShortcutStore.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var feedback: String?
  @State private var feedbackRevision = 0
  @State private var qrInput = ""
  @State private var webQuery = ""
  @State private var calculation = ""
  @State private var scientific = false
  @FocusState private var calculationFocused: Bool
  @State private var showingMacros = false
  @State private var macroName = ""
  @State private var macroCommand = ""
  @State private var macReadings: MacReadings?
  @State private var documentFonts = ""
  @State private var deliveredAlerts = ""
  @State private var dashboardPage: Int? = 0
  @State private var openStack: UUID?
  @State private var stackRename = ""
  @State private var renamingStack = false

  var body: some View {
    VStack(spacing: 7) {
      header
      Group {
        if shelf.choosingArrow { ArrowFinder(shelf: shelf) }
        else if shelf.activeModule == .dashboard { widgetDashboard }
        else { moduleBody }
      }
        .id(shelf.choosingArrow ? "finder" : shelf.activeModule.rawValue)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .offset(y: 4)))
      HStack {
        if let feedback {
          Text(feedback).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer()
        if shelf.choosingArrow {
          Text("↑ ↓  Select     ↩  Open     Esc  Back").font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
          Button(action: shelf.chooseArrow) {
            Label("Find an arrow", systemImage: "magnifyingglass")
            Text(shortcuts.binding(for: .chooseArrow).displayName).monospaced()
          }
          .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
          .accessibilityLabel("Find an arrow")
        }

      }
    }
    .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 7)
    .animation(reduceMotion ? nil : .smooth(duration: 0.23), value: shelf.activeModule)
    .animation(reduceMotion ? nil : .smooth(duration: 0.23), value: shelf.choosingArrow)
    .onReceive(tools.$status.dropFirst()) { status in
      feedback = status
      feedbackRevision += 1
    }
    .task(id: feedbackRevision) {
      guard feedback != nil else { return }
      do { try await Task.sleep(for: .seconds(3)) } catch { return }
      feedback = nil
    }
    .task(id: shelf.activeModule.rawValue + (shelf.isArrowPreview ? "-preview" : "-open")) {
      if shelf.activeModule == .system {
        var last: MacReadings.Sample?
        while !Task.isCancelled {
          let current = MacReadings.Sample()
          macReadings = MacReadings(current, previous: last)
          last = current
          try? await Task.sleep(for: .seconds(2))
        }
        return
      }
      if shelf.activeModule == .dashboard || shelf.activeModule == .downloads { await tools.refreshDownloads() }
      if shelf.activeModule == .calendar, EKEventStore.authorizationStatus(for: .event) == .fullAccess {
        tools.refreshCalendar()
      }
      guard !shelf.isArrowPreview, shelf.activeModule == .dashboard || shelf.activeModule == .music else { return }
      while !Task.isCancelled {
        tools.refreshMedia()
        try? await Task.sleep(for: .seconds(2))
      }
    }
  }

  private var header: some View {
    HStack(spacing: 7) {
      NotchIconButton(symbol: "xmark", help: "Close Skippy", action: shelf.dismiss)
      ZStack {
        Circle().fill(skin.palette.accent.opacity(0.18))
        Image(systemName: shelf.choosingArrow ? "magnifyingglass" : shelf.activeModule.symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(skin.palette.accent)
      }.frame(width: 26, height: 26)
      VStack(alignment: .leading, spacing: 0) {
        Text(shelf.choosingArrow ? "Arrows" : shelf.activeModule.title).font(.system(size: 16, weight: .semibold))
        Text(shelf.choosingArrow ? "\(NotchModule.allCases.count - 1) tools" : headerSubtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer()
      if shelf.choosingArrow {
        NotchIconButton(symbol: "chevron.backward", help: "Back to tool", action: shelf.cancelChoosingArrow)
      } else if shelf.activeModule == .dashboard {
        NotchIconButton(symbol: widgets.editing ? "checkmark" : "slider.horizontal.3", tint: skin.palette.accent,
          selected: widgets.editing, help: widgets.editing ? "Finish arranging" : "Arrange widgets") {
          withAnimation(Motion.layoutRelayout) { widgets.editing.toggle() }
        }
      } else {
        NotchIconButton(symbol: shelf.keepArrowOpen ? "pin.fill" : "pin", tint: skin.palette.accent,
          selected: shelf.keepArrowOpen, help: shelf.keepArrowOpen ? "Unpin panel" : "Keep panel open") {
          shelf.toggleArrowRetention()
        }
        NotchIconButton(symbol: "square.grid.2x2", tint: skin.palette.accent,
          help: "Back to widgets", action: { shelf.showModule(.dashboard) })
      }
      NotchIconButton(symbol: "gearshape", help: "Settings", action: AppController.shared.openPreferences)
    }
  }

  private var headerSubtitle: String {
    switch shelf.activeModule {
    case .dashboard: widgets.editing ? "Drag, resize and pin widgets" : "Your quiver"
    case .parcel: "Everything ready to move"
    case .clipboard: "Your recent copies"
    case .extract: "Private, on-device OCR"
    case .color: "Sample any pixel"
    case .timer: tools.timerEnd == nil ? "Start a focus session" : "Focus session running"
    case .notes: "Saved automatically"
    case .qr: "Create or read a code"
    case .search: "Search without opening a browser first"
    case .launcher: "Running on this Mac"
    case .music: tools.mediaSource ?? "Local and system playback"
    case .downloads: "Recent files, ready to open"
    case .awake: tools.isKeepingAwake ? "Sleep is paused" : "Keep long tasks running"
    case .recent: "Recall what you just did"
    case .system: "A quick Mac glance"
    case .calendar: "Upcoming events"
    case .calculator: "Calculate privately on your Mac"
    case .screenshot: "Capture and combine regions"
    case .draw: "Annotate your screen"
    case .convert, .compress, .extractArchive: "Save results to the File Shelf"
    }
  }

  @ViewBuilder private var moduleBody: some View {
    switch shelf.activeModule {
    case .dashboard: EmptyView()
    case .parcel: parcelSummary
    case .clipboard: clipboardView
    case .extract: extractView
    case .color: colourView
    case .timer: timerView
    case .notes: notesView
    case .qr: qrView
    case .search: searchView
    case .launcher: launcherView
    case .music: musicView
    case .downloads: downloadsView
    case .awake: awakeView
    case .recent: recentView
    case .system: systemView
    case .calendar: calendarView
    case .calculator: calculatorView
    case .screenshot: screenshotView
    case .draw: drawView
    case .convert: ShelfFileActionView(store: store, operation: .convert)
    case .compress: ShelfFileActionView(store: store, operation: .compress)
    case .extractArchive: ShelfFileActionView(store: store, operation: .extract)
    }
  }

  private var widgetDashboard: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(spacing: 0) {
        ForEach(Array(widgets.pages.enumerated()), id: \.offset) { page, pageWidgets in
          NotchWidgetGridLayout {
            ForEach(pageWidgets) { widget in
              dashboardWidget(widget)
                .notchWidgetSpan(widget.size)
                .dropDestination(for: String.self) { values, _ in
                  guard let raw = values.first, let source = NotchWidgetKind(rawValue: raw) else { return false }
                  withAnimation(Motion.layoutRelayout) { widgets.move(source, before: widget.kind) }
                  return true
                }
            }
          }
          .frame(maxHeight: .infinity, alignment: .top)
          .containerRelativeFrame(.vertical)
          .id(page)
        }
      }
      .scrollTargetLayout()
      .animation(Motion.layoutRelayout, value: widgets.widgets)
    }
    .scrollClipDisabled()
    .scrollPosition(id: $dashboardPage)
    .scrollTargetBehavior(.paging)
    .overlay(alignment: .bottom) {
      if widgets.pages.count > 1 {
        HStack(spacing: 5) {
          ForEach(widgets.pages.indices, id: \.self) { page in
            Circle().fill(page == (dashboardPage ?? 0) ? skin.palette.accent : Color.secondary.opacity(0.35))
              .frame(width: 5, height: 5)
          }
        }.padding(.horizontal, 7).padding(.vertical, 5)
          .background(.ultraThinMaterial, in: Capsule())
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .parcelsNextWidgetPage)) { _ in movePage(1) }
    .onReceive(NotificationCenter.default.publisher(for: .parcelsPreviousWidgetPage)) { _ in movePage(-1) }
    .onChange(of: widgets.pages.count) { _, count in dashboardPage = min(dashboardPage ?? 0, max(0, count - 1)) }
  }

  private func movePage(_ step: Int) {
    let count = widgets.pages.count
    guard count > 0 else { return }
    withAnimation(Motion.layoutRelayout) {
      dashboardPage = ((dashboardPage ?? 0) + step % count + count) % count
    }
  }

  @ViewBuilder private func dashboardWidget(_ widget: NotchWidget) -> some View {
    let card = Group {
      if widget.kind == .launcher, widget.size == .fourByFour { launcherWidget(widget) }
      else {
        Button { if !widgets.editing { shelf.showModule(widget.kind.module) } } label: {
          widgetContents(widget)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(widget.size == .oneByOne ? 8 : 10)
        }
        .buttonStyle(NotchWidgetButtonStyle(tint: skin.palette.accent))
      }
    }
    .overlay(alignment: .topTrailing) {
      if widgets.editing {
        Menu {
          ForEach(NotchWidgetSize.allCases) { size in
            Button { widgets.resize(widget.kind, to: size) } label: {
              if widget.size == size { Label(size.label, systemImage: "checkmark") }
              else { Text(size.label) }
            }
          }
        } label: {
          Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 8, weight: .bold))
            .foregroundStyle(.secondary).padding(6)
        }.menuStyle(.borderlessButton).fixedSize()
      } else if widget.pinned {
        Image(systemName: "pin.fill").font(.system(size: 7, weight: .bold))
          .foregroundStyle(skin.palette.accent).padding(6)
      }
    }
    let contextualCard = Group {
      // Keep the launcher's nested app menus reachable. A context menu on the
      // parent swallows every right-click before an individual app sees it.
      if widget.kind == .launcher { card }
      else {
        card.contextMenu {
          Menu("Widget size") {
            ForEach(NotchWidgetSize.allCases) { size in
              Button { widgets.resize(widget.kind, to: size) } label: {
                if widget.size == size { Label(size.label, systemImage: "checkmark") }
                else { Text(size.label) }
              }
            }
          }
          Button(widget.pinned ? "Remove from quiver" : "Pin to quiver") {
            widgets.togglePinned(widget.kind)
          }
          Button("Open") { shelf.showModule(widget.kind.module) }
        }
      }
    }
    if widgets.editing { contextualCard.draggable(widget.kind.rawValue) }
    else { contextualCard }
  }

  @ViewBuilder private func widgetContents(_ widget: NotchWidget) -> some View {
    switch widget.size {
    case .oneByOne:
      VStack(alignment: .leading, spacing: 3) {
        Image(systemName: widget.kind.module.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(skin.palette.accent)
        Spacer(minLength: 0)
        Text(widgetCompactValue(widget.kind)).font(.system(size: 9, weight: .semibold, design: .rounded)).lineLimit(1)
      }
    case .oneByTwo:
      VStack(alignment: .leading, spacing: 5) {
        Image(systemName: widget.kind.module.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(skin.palette.accent)
        Spacer(minLength: 0)
        Text(widget.kind.module.title).font(.system(size: 10, weight: .semibold)).lineLimit(2)
        Text(widgetSubtitle(widget.kind)).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(3)
      }
    case .twoByOne:
      HStack(spacing: 8) {
        Image(systemName: widget.kind.module.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(skin.palette.accent)
          .frame(width: 28, height: 28).background(skin.palette.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
        VStack(alignment: .leading, spacing: 2) {
          Text(widget.kind.module.title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
          Text(widgetSubtitle(widget.kind)).font(.system(size: 8.5)).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer(minLength: 0)
      }
    case .twoByTwo, .fourByFour:
      VStack(alignment: .leading, spacing: 7) {
        NotchSectionTitle(title: widget.kind.module.title, symbol: widget.kind.module.symbol)
        Text(widgetHeroValue(widget.kind)).font(.system(size: widget.size == .fourByFour ? 22 : 16,
          weight: .semibold, design: .rounded)).lineLimit(2)
        Spacer(minLength: 0)
        Text(widgetSubtitle(widget.kind)).font(.system(size: 8.5)).foregroundStyle(.secondary).lineLimit(widget.size == .fourByFour ? 4 : 2)
        if widget.kind == .music, tools.mediaIsPlaying {
          HStack(spacing: 3) { ForEach(0..<9, id: \.self) { index in
            Capsule().fill(skin.palette.accent).frame(width: 3, height: CGFloat(4 + (index * 7) % 15))
          }}.frame(height: 19, alignment: .bottom)
        }
      }
    }
  }

  private func launcherWidget(_ widget: NotchWidget) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        NotchSectionTitle(title: "Apps", symbol: "square.grid.2x2", trailing: "Click to open")
        Button("View all") { if !widgets.editing { shelf.showModule(.launcher) } }
          .buttonStyle(.plain).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(skin.palette.accent)
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 7) {
        ForEach(tools.launchableApps.prefix(18), id: \.processIdentifier) { app in
          Button { if !widgets.editing { tools.activate(app) } } label: {
            VStack(spacing: 3) {
              Image(nsImage: app.icon ?? NSImage()).resizable().frame(width: 26, height: 26)
              Text(app.localizedName ?? "App").font(.system(size: 7.5, weight: .medium)).lineLimit(1)
            }.frame(maxWidth: .infinity)
          }.buttonStyle(.plain).help(app.localizedName ?? "App")
            .contextMenu {
              Button(tools.isPinned(app) ? "Remove from quiver" : "Pin to quiver") { tools.togglePinned(app) }
              Button("Open") { tools.activate(app) }
            }
        }
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .background(skin.palette.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.065), lineWidth: 0.8))
  }

  private func widgetCompactValue(_ kind: NotchWidgetKind) -> String {
    switch kind {
    case .parcel: "\(shelf.primaryBox?.items.count ?? 0) files"
    case .clipboard: "\(clipboard.entries.count) copies"
    case .timer: tools.timerEnd == nil ? "Timer" : timerLabel
    case .notes: tools.note.isEmpty ? "Note" : "Saved"
    case .music: tools.mediaIsPlaying ? "Playing" : "Music"
    case .downloads: "\(tools.downloads.count) recent"
    case .awake: tools.isKeepingAwake ? "Awake" : "Sleep"
    case .recent: "\(recent.actions.count) actions"
    case .launcher: "\(tools.launchableApps.count) apps"
    default: kind.module.title
    }
  }

  private func widgetHeroValue(_ kind: NotchWidgetKind) -> String {
    switch kind {
    case .parcel: shelf.primaryBox?.name ?? "New parcel"
    case .clipboard: "\(clipboard.entries.count) recent copies"
    case .timer: tools.timerEnd == nil ? "25:00" : timerLabel
    case .notes: tools.note.isEmpty ? "Capture a thought" : String(tools.note.prefix(54))
    case .music: tools.mediaTitle
    case .downloads: tools.downloads.first?.lastPathComponent ?? "No downloads"
    case .awake: tools.isKeepingAwake ? "Staying awake" : "Normal sleep"
    case .recent: recent.actions.first?.title ?? "No recent actions"
    case .system: ProcessInfo.processInfo.operatingSystemVersionString
    default: kind.module.title
    }
  }

  private func widgetSubtitle(_ kind: NotchWidgetKind) -> String {
    switch kind {
    case .parcel: "Drop, collect, transform and share files."
    case .clipboard: "Text, images and files — searchable."
    case .extract: "Read text from images privately on this Mac."
    case .color: "\(tools.pickedColour) · click to sample"
    case .timer: tools.timerEnd == nil ? "Start a focus session" : "Focus session running"
    case .notes: "Saved automatically"
    case .qr: "Generate or scan QR codes"
    case .search: "Search the web from the notch"
    case .launcher: "Running apps"
    case .music: tools.mediaArtist
    case .downloads: "Latest files from Downloads"
    case .awake: tools.isKeepingAwake ? "Click to restore normal sleep" : "Click to prevent display and system sleep"
    case .recent: "Copies, packs and conversions"
    case .system: "\(ProcessInfo.processInfo.activeProcessorCount) cores · \(uptime(ProcessInfo.processInfo.systemUptime)) uptime"
    case .calendar: "Upcoming meetings and events"
    case .calculator: "Quick arithmetic"
    case .screenshot: "Join screen regions into one image"
    case .draw: "Sketch, highlight and draw shapes"
    }
  }

  private var parcelSummary: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let box = shelf.primaryBox {
        HStack(spacing: 8) {
          Label(box.name, systemImage: "shippingbox").font(.headline).lineLimit(1)
          Spacer()
          Text("\(box.items.count) items").font(.caption).foregroundStyle(.secondary)
        }
        HStack(spacing: 8) {
          NotchActionButton(title: "Add", symbol: "plus", tint: skin.palette.accent) {
            store.selectBox(box.id); store.addFilesPanel()
          }
          NotchActionButton(title: "Paste", symbol: "doc.on.clipboard", tint: skin.palette.accent, action: shelf.pasteFiles)
          NotchActionButton(title: "Pack", symbol: "archivebox", tint: skin.palette.accent, action: shelf.pack)
          if store.selectedItems.count > 1 {
            Button("Stack selected") { store.stackSelected() }
          }
          Spacer()
        }
        Divider().opacity(0.45)
        if let openStack, box.items.contains(where: { $0.stackID == openStack }) {
          stackDetails(openStack, in: box)
        } else {
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 9) {
              ForEach(store.compactItems(box.items)) { item in
                shelfIcon(item, in: box)
              }
              if box.items.isEmpty {
                Label("Drop or paste files here", systemImage: "arrow.down.doc")
                  .font(.caption).foregroundStyle(.secondary).padding(15)
              }
            }.frame(maxHeight: .infinity, alignment: .topLeading)
          }
        }
      }
    }
    .padding(10)
    .background(skin.palette.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .background {
      FileDropSurface(enabled: !store.busy, receive: { _ in }, receiving: { _ in }, hover: { _ in },
        failure: { _ in }, beginDrop: shelf.beginPrimaryDrop)
    }
  }

  private func shelfIcon(_ item: ParcelItem, in box: ParcelBox) -> some View {
    let members = store.stackMembers(of: item, in: box)
    let available = members.filter { FileManager.default.fileExists(atPath: $0.effectiveURL.path) }
    let grouped = members.count > 1
    let title = grouped ? item.stackName ?? "Stack" : item.effectiveName
    let open = {
      if NSEvent.modifierFlags.contains(.command) {
        if store.selectedBox != box.id { store.selectBox(box.id) }
        store.toggleSelection(item.id)
      } else if grouped { openStack = item.stackID }
      else if let first = available.first { NSWorkspace.shared.open(first.effectiveURL) }
    }
    return VStack(spacing: 5) {
      ZStack(alignment: .bottomTrailing) {
        if grouped {
          RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(0.14)).frame(width: 35, height: 34).offset(x: 4, y: -4)
        }
        Image(nsImage: NSWorkspace.shared.icon(forFile: item.effectiveURL.path))
          .resizable().aspectRatio(contentMode: .fit).frame(width: 36, height: 38)
        if grouped {
          Text("\(members.count)").font(.caption2.bold()).padding(3).background(.regularMaterial, in: Capsule())
        }
      }
      Text(title).font(.caption).lineLimit(2).frame(width: 89)
      if available.count != members.count {
        Text("\(members.count - available.count) missing").font(.caption2).foregroundStyle(.orange)
      }
    }.padding(7)
      .background(Color.primary.opacity(store.selectedItems.contains(item.id) ? 0.18 : 0.06), in: RoundedRectangle(cornerRadius: 10))
      .overlay {
        DragOutSurface(urls: available.map(\.effectiveURL), tap: open, menu: { _ in
          shelf.fileContextMenu(for: item)
        })
      }
      .accessibilityLabel(title)
      .help(grouped ? "Open stack · Drag all items · Command-click to select" : "Open file · Command-click to select")
  }

  private func stackDetails(_ id: UUID, in box: ParcelBox) -> some View {
    let members = box.items.filter { $0.stackID == id }
    return VStack(alignment: .leading, spacing: 5) {
      HStack {
        Button("Back") { openStack = nil }
        Text(members.first?.stackName ?? "Stack").font(.headline)
        Spacer()
        Button("Rename…") {
          stackRename = members.first?.stackName ?? ""
          renamingStack = true
        }
        Button("Ungroup") {
          if let first = members.first {
            if store.selectedBox != box.id { store.selectBox(box.id) }
            store.unstack(first.id)
            openStack = nil
          }
        }
      }
      ScrollView {
        ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
          HStack {
            Text(member.effectiveName).lineLimit(1)
            if !FileManager.default.fileExists(atPath: member.effectiveURL.path) {
              Text("Missing").foregroundStyle(.orange)
            }
            Spacer()
            Button { store.moveStackMember(member.id, in: box.id, by: -1) } label: { Image(systemName: "arrow.up") }
              .accessibilityLabel("Move \(member.effectiveName) up").disabled(index == 0)
            Button { store.moveStackMember(member.id, in: box.id, by: 1) } label: { Image(systemName: "arrow.down") }
              .accessibilityLabel("Move \(member.effectiveName) down").disabled(index == members.count - 1)
          }.buttonStyle(.borderless).font(.caption)
        }
      }
    }
    .alert("Rename Stack", isPresented: $renamingStack) {
      TextField("Stack name", text: $stackRename)
      Button("Save") { store.renameStack(id, in: box.id, to: stackRename) }
      Button("Cancel", role: .cancel) {}
    }
  }

  private var clipboardView: some View {
    VStack(spacing: 6) {
      HStack(spacing: 7) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Search text, images and files", text: $clipboard.search).textFieldStyle(.plain)
      }.padding(.horizontal, 10).frame(height: 30)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      ScrollView {
        LazyVStack(spacing: 4) {
          if clipboard.filtered.isEmpty {
            ContentUnavailableView {
              Label(clipboard.search.isEmpty ? (clipboard.captureEnabled ? "Clipboard is empty" : "Capture is paused")
                                             : "No matching copies", systemImage: "list.clipboard")
            } description: {
              Text(clipboard.search.isEmpty ? (clipboard.captureEnabled ? "Copy text, an image or a file to see it here."
                                                                       : "Resume clipboard capture in Settings.")
                                            : "Try a different search.")
            }
          }
          ForEach(clipboard.filtered) { entry in
            ClipboardHistoryRow(entry: entry, history: clipboard, skin: skin,
                                addToParcel: shelf.addClipboardEntry, processImage: shelf.processClipboardImage)
          }
        }
      }
    }
  }

  private var extractView: some View {
    HStack(spacing: 8) {
      NotchCard(tint: skin.palette.accent) {
        VStack(spacing: 12) {
          ZStack {
            RoundedRectangle(cornerRadius: 15).fill(skin.palette.accent.opacity(0.13)).frame(width: 66, height: 66)
            Image(systemName: "text.viewfinder").font(.system(size: 29, weight: .light)).foregroundStyle(skin.palette.accent)
          }
          Text("Text extraction").font(.system(size: 12, weight: .semibold))
          Button("Inspect fonts in a PDF…", action: inspectFonts)
          if !documentFonts.isEmpty {
            ScrollView { Text(documentFonts).font(.caption).textSelection(.enabled) }.frame(maxHeight: 50)
          }
          Text("Vision reads images locally. Nothing is uploaded.").font(.system(size: 8.5)).multilineTextAlignment(.center).foregroundStyle(.secondary)
          HStack(spacing: 5) {
            NotchActionButton(title: "Screen", symbol: "viewfinder", tint: skin.palette.accent, action: tools.extractFromScreen)
            NotchActionButton(title: "Clipboard", symbol: "clipboard", tint: skin.palette.accent, action: tools.extractFromClipboard)
            NotchActionButton(title: "Choose", symbol: "photo", tint: skin.palette.accent, action: tools.chooseImageForOCR)
          }
        }
      }.frame(width: tools.ocrText.isEmpty ? nil : 205)
      if !tools.ocrText.isEmpty {
        NotchCard {
          VStack(alignment: .leading, spacing: 7) {
            NotchSectionTitle(title: "Extracted", symbol: "text.quote")
            ScrollView { Text(tools.ocrText).textSelection(.enabled).font(.system(size: 9.5)).frame(maxWidth: .infinity, alignment: .leading) }
            NotchActionButton(title: "Summarise", symbol: "apple.intelligence", tint: skin.palette.accent) {
              tools.summarizeWithAppleIntelligence(tools.ocrText)
            }.disabled(tools.intelligenceWorking)
          }
        }
      }
    }
  }

  private func inspectFonts() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.pdf]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    Task {
      documentFonts = await Task.detached(priority: .userInitiated) {
        guard let document = PDFDocument(url: url), !document.isLocked else { return "The PDF could not be read." }
        var names = Set<String>()
        for page in 0..<document.pageCount {
          guard let text = document.page(at: page)?.attributedString else { continue }
          text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let font = value as? NSFont { names.insert(font.fontName) }
          }
        }
        return names.isEmpty ? "No selectable text with font information." : names.sorted().joined(separator: ", ")
      }.value
    }
  }

  private var colourView: some View {
    HStack(spacing: 18) {
      ZStack {
        Circle().stroke(Color.white.opacity(0.14), lineWidth: 8).frame(width: 116, height: 116)
        Circle().fill(Color(nsColor: NSColor(hex: tools.pickedColour) ?? .systemGreen)).frame(width: 91, height: 91)
          .shadow(color: Color(nsColor: NSColor(hex: tools.pickedColour) ?? .systemGreen).opacity(0.35), radius: 18)
        Image(systemName: "eyedropper").font(.system(size: 20, weight: .medium)).foregroundStyle(.white)
      }
      VStack(alignment: .leading, spacing: 10) {
        NotchSectionTitle(title: "Current colour", symbol: "paintpalette")
        Text(tools.pickedColour).font(.system(size: 24, weight: .semibold, design: .rounded)).monospaced()
        Text("Pick anywhere on any display. The HEX value is copied instantly.")
          .font(.system(size: 9)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        NotchActionButton(title: "Pick a pixel", symbol: "eyedropper.halffull", tint: skin.palette.accent,
          action: tools.pickColour)
      }.frame(maxWidth: 230, alignment: .leading)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var timerView: some View {
    HStack(spacing: 18) {
      ZStack {
        Circle().stroke(Color.primary.opacity(0.08), lineWidth: 8)
        Circle().trim(from: 0, to: timerProgress).stroke(skin.palette.accent,
          style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
          .animation(.linear(duration: 0.25), value: tools.remaining)
        Text(timerLabel).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
      }.frame(width: 126, height: 126)
      VStack(alignment: .leading, spacing: 11) {
        NotchSectionTitle(title: "Focus timer", symbol: "timer")
        Stepper("\(tools.timerMinutes) minutes", value: $tools.timerMinutes, in: 1...180)
          .font(.system(size: 11, weight: .medium)).frame(width: 170)
        Toggle("Keep Mac awake", isOn: $tools.keepAwakeDuringTimer)
          .toggleStyle(.checkbox).font(.system(size: 10))
        HStack(spacing: 6) {
          NotchActionButton(title: tools.timerEnd == nil ? "Start" : "Restart",
            symbol: tools.timerEnd == nil ? "play.fill" : "arrow.clockwise", tint: skin.palette.accent,
            action: tools.startTimer)
          if tools.timerEnd != nil {
            NotchActionButton(title: "Stop", symbol: "stop.fill", tint: .red, action: tools.stopTimer)
          }
        }
        Text("Reopen the Timer arrow to check your countdown.").font(.system(size: 8.5)).foregroundStyle(.secondary)
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var timerProgress: CGFloat {
    guard tools.timerEnd != nil else { return 0 }
    return max(0, min(1, tools.remaining / TimeInterval(max(1, tools.timerMinutes) * 60)))
  }

  private var timerLabel: String {
    let value = tools.timerEnd == nil ? TimeInterval(tools.timerMinutes * 60) : tools.remaining
    return String(format: "%02d:%02d", Int(value) / 60, Int(value) % 60)
  }

  private var notesView: some View {
    HStack(spacing: 8) {
      VStack(spacing: 6) {
        HStack { NotchSectionTitle(title: "Quick note", symbol: "note.text"); Text("Saved automatically").font(.system(size: 8)).foregroundStyle(.secondary) }
        TextEditor(text: $tools.note).accessibilityLabel("Quick note").font(.body).scrollContentBackground(.hidden)
          .padding(9).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
      VStack(spacing: 7) {
        NotchActionButton(title: "Summarise", symbol: "apple.intelligence", tint: skin.palette.accent) {
          tools.summarizeWithAppleIntelligence(tools.note)
        }.disabled(tools.intelligenceWorking)
        NotchActionButton(title: "Copy note", symbol: "doc.on.doc", tint: skin.palette.accent) {
          tools.copyText(tools.note, label: "Note")
        }
        Spacer()
        if !tools.intelligenceResult.isEmpty {
          Text(tools.intelligenceResult).font(.system(size: 8.5)).lineLimit(6).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            .background(skin.palette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
      }.frame(width: 132)
    }
  }

  private var qrView: some View {
    HStack(spacing: 14) {
      ZStack {
        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white)
        if let image = tools.generateQR(qrInput) {
          Image(nsImage: image).interpolation(.none).resizable().padding(12)
        } else {
          Image(systemName: "qrcode").font(.system(size: 62)).foregroundStyle(.black.opacity(0.22))
        }
      }.frame(width: 142, height: 142).shadow(color: .black.opacity(0.14), radius: 12, y: 5)
      VStack(alignment: .leading, spacing: 9) {
        NotchSectionTitle(title: "QR tools", symbol: "qrcode.viewfinder")
        HStack(spacing: 7) {
          Image(systemName: "text.cursor").foregroundStyle(.secondary)
          TextField("Text, Wi-Fi details or a link", text: $qrInput).textFieldStyle(.plain)
        }.padding(.horizontal, 9).frame(height: 31)
          .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        HStack(spacing: 6) {
          NotchActionButton(title: "Copy QR", symbol: "doc.on.doc", tint: skin.palette.accent) { tools.copyQR(qrInput) }
          NotchActionButton(title: "Scan screen", symbol: "viewfinder", tint: skin.palette.accent, action: tools.scanScreenQR)
        }
        HStack(spacing: 6) {
          NotchActionButton(title: "Scan clipboard", symbol: "doc.on.clipboard", tint: skin.palette.accent, action: tools.scanClipboardQR)
          NotchActionButton(title: "Image", symbol: "photo", tint: skin.palette.accent, action: tools.scanQR)
        }
        if !tools.qrText.isEmpty {
          Text(tools.qrText).font(.system(size: 8.5)).lineLimit(3).textSelection(.enabled)
            .padding(7).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var searchView: some View {
    VStack(spacing: 13) {
      Spacer()
      HStack(spacing: 9) {
        Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(skin.palette.accent)
        TextField("Search Google", text: $webQuery).textFieldStyle(.plain).font(.system(size: 14, weight: .medium))
          .onSubmit { tools.searchGoogle(webQuery) }
        if !webQuery.isEmpty {
          Button { webQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        Text("↩").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
      }.padding(.horizontal, 14).frame(height: 46)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(skin.palette.accent.opacity(0.22), lineWidth: 1))
      HStack(spacing: 6) {
        suggestion("parcel workflows"); suggestion("convert PDF on Mac"); suggestion("share files securely")
      }
      Text("Your query opens in the default browser. Skippy never records it.").font(.system(size: 8.5)).foregroundStyle(.secondary)
      Spacer()
    }.frame(maxWidth: 390)
  }

  private var launcherView: some View {
    VStack(spacing: 7) {
      Picker("Launcher", selection: $showingMacros) {
        Text("Apps").tag(false)
        Text("Commands").tag(true)
      }.pickerStyle(.segmented).labelsHidden()
      if showingMacros { macroView }
      else { appLauncherGrid }
    }
  }

  private var appLauncherGrid: some View {
    ScrollView(showsIndicators: false) {
      HStack {
        Text("PINNED").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
        Spacer()
        Button("Add app…") { tools.choosePinnedApp() }.buttonStyle(.borderless)
      }.padding(.bottom, 4)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 9) {
        ForEach(tools.pinnedApps) { app in
          Button { tools.launch(app) } label: {
            VStack(spacing: 5) {
              Image(nsImage: tools.icon(for: app)).resizable().frame(width: 34, height: 34)
              Text(app.name).font(.system(size: 8.5, weight: .medium)).lineLimit(1)
            }.frame(maxWidth: .infinity)
          }.buttonStyle(.plain).contextMenu { Button("Unpin") { tools.unpinApp(app) } }
        }
      }
      if !tools.launchableApps.isEmpty {
        Text("RUNNING").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 7)
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 9) {
        ForEach(tools.launchableApps, id: \.processIdentifier) { app in
          ZStack(alignment: .topTrailing) {
            Button { tools.activate(app) } label: {
              VStack(spacing: 5) {
                Image(nsImage: app.icon ?? NSImage()).resizable().frame(width: 34, height: 34)
                Text(app.localizedName ?? "App").font(.system(size: 8.5, weight: .medium)).lineLimit(1)
              }
              .frame(maxWidth: .infinity).padding(.vertical, 5)
              .background(Color.primary.opacity(0.001), in: RoundedRectangle(cornerRadius: 11))
            }.buttonStyle(.plain)
              .contextMenu {
                Button(tools.isPinned(app) ? "Remove from quiver" : "Pin to quiver") { tools.togglePinned(app) }
                Button("Open") { tools.activate(app) }
              }
            Button { tools.togglePinned(app) } label: {
              Image(systemName: tools.isPinned(app) ? "pin.fill" : "pin")
                .font(.system(size: 10, weight: .semibold)).frame(width: 20, height: 20)
                .background(.regularMaterial, in: Circle())
            }.buttonStyle(.plain)
              .accessibilityLabel((tools.isPinned(app) ? "Unpin " : "Pin ") + (app.localizedName ?? "application"))
          }
        }
      }
    }
  }

  private var macroView: some View {
    VStack(spacing: 6) {
      HStack {
        TextField("Name", text: $macroName).textFieldStyle(.roundedBorder).frame(width: 95)
        TextField("Shell command", text: $macroCommand).textFieldStyle(.roundedBorder)
        Button("Add") {
          guard !macroName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !macroCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
          tools.addMacro(name: macroName, command: macroCommand)
          macroName = ""; macroCommand = ""
        }
      }
      ScrollView {
        LazyVStack(spacing: 5) {
          ForEach(tools.macros) { macro in
            HStack {
              VStack(alignment: .leading) {
                Text(macro.name).font(.system(size: 10, weight: .semibold))
                Text(macro.command).font(.system(size: 9, design: .monospaced)).lineLimit(1).foregroundStyle(.secondary)
              }
              Spacer()
              Button("Run") { tools.runMacro(macro) }
              Button { tools.removeMacro(macro) } label: { Image(systemName: "trash") }
                .help("Remove command")
            }.padding(7).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
          }
        }
      }
      Text("Commands run with your account permissions after confirmation.")
        .font(.system(size: 8)).foregroundStyle(.secondary)
    }
  }

  private var musicView: some View {
    HStack(spacing: 14) {
      ZStack {
        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(
          LinearGradient(colors: [skin.palette.accent, skin.palette.accentSoft.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
        Image(systemName: tools.mediaIsPlaying || tools.isPlaying ? "waveform" : "music.note")
          .font(.system(size: 42, weight: .medium)).foregroundStyle(.white)
          .symbolEffect(.variableColor.iterative, isActive: tools.mediaIsPlaying || tools.isPlaying)
      }.frame(width: 142, height: 142).shadow(color: skin.palette.accent.opacity(0.25), radius: 14, y: 6)
      VStack(alignment: .leading, spacing: 8) {
        if let source = tools.mediaSource {
          Text(source.uppercased()).font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(skin.palette.accent)
        }
        Text(tools.mediaTitle).font(.system(size: 15, weight: .semibold)).lineLimit(2)
        Text(tools.mediaArtist).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        HStack(spacing: 10) {
          mediaButton("backward.fill", action: { tools.controlMedia(.previous) })
          mediaButton(tools.mediaIsPlaying || tools.isPlaying ? "pause.fill" : "play.fill", prominent: true,
            action: { tools.controlMedia(.toggle) })
          mediaButton("forward.fill", action: { tools.controlMedia(.next) })
        }
        NotchActionButton(title: "Play a local file", symbol: "folder", tint: skin.palette.accent) {
          tools.chooseAudio()
          shelf.focusForKeyboard()
        }
      }.frame(maxWidth: 240, alignment: .leading)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var downloadsView: some View {
    VStack(spacing: 8) {
      HStack {
        NotchSectionTitle(title: "Recent downloads", symbol: "arrow.down.circle")
        Spacer()
        Button("Open Downloads", action: tools.openDownloads)
          .buttonStyle(.plain).font(.system(size: 9, weight: .semibold)).foregroundStyle(skin.palette.accent)
      }
      if tools.downloads.isEmpty {
        ContentUnavailableView("No recent downloads", systemImage: "arrow.down.circle")
      } else {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
          ForEach(tools.downloads.prefix(8), id: \.self) { url in
            Button { NSWorkspace.shared.open(url) } label: {
              VStack(spacing: 4) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                  .aspectRatio(contentMode: .fit).frame(width: 30, height: 30)
                Text(url.lastPathComponent).font(.system(size: 8, weight: .medium)).lineLimit(1)
              }.frame(maxWidth: .infinity).padding(6)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).help(url.lastPathComponent)
          }
        }
      }
    }
  }

  private var awakeView: some View {
    VStack(spacing: 14) {
      Image(systemName: tools.isKeepingAwake ? "sun.max.fill" : "moon.zzz.fill")
        .font(.system(size: 48, weight: .medium)).foregroundStyle(skin.palette.accent)
      Text(tools.isKeepingAwake ? "Your Mac will stay awake" : "Normal sleep is active")
        .font(.system(size: 15, weight: .semibold))
      Text("Useful during uploads, renders and long-running automations.")
        .font(.system(size: 9.5)).foregroundStyle(.secondary)
      NotchActionButton(title: tools.isKeepingAwake ? "Allow sleep" : "Stay awake",
        symbol: tools.isKeepingAwake ? "moon.zzz" : "cup.and.saucer.fill",
        tint: skin.palette.accent, action: tools.toggleStayAwake)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var recentView: some View {
    VStack(spacing: 6) {
      if recent.actions.isEmpty {
        ContentUnavailableView("No recent actions", systemImage: "clock.arrow.circlepath")
      } else {
        ForEach(recent.actions.prefix(6)) { action in
          HStack(spacing: 8) {
            Image(systemName: action.symbol).foregroundStyle(skin.palette.accent).frame(width: 24)
            Text(action.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
            Spacer()
          }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 31)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        }
      }
    }
  }

  private var drawView: some View {
    VStack(spacing: 12) {
      Image(systemName: "pencil.tip.crop.circle").font(.system(size: 40)).foregroundStyle(skin.palette.accent)
      Text("Draw over your screen").font(.system(size: 14, weight: .semibold))
      Text("Draw, erase or save the annotation layer as a transparent PNG.")
        .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
      NotchActionButton(title: "Start drawing", symbol: "pencil.tip", tint: skin.palette.accent) {
        shelf.dismiss()
        ScreenMarkupController.shared.open()
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var calendarView: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(tools.calendarMessage).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        Spacer()
        Button("Connect") { tools.connectCalendar() }.buttonStyle(.bordered)
        Button { tools.refreshCalendar() } label: { Image(systemName: "arrow.clockwise") }
          .buttonStyle(.borderless).help("Refresh events")
      }
      ScrollView {
        LazyVStack(spacing: 6) {
          ForEach(tools.calendarEvents, id: \.eventIdentifier) { event in
            HStack(spacing: 9) {
              Image(systemName: "calendar").foregroundStyle(skin.palette.accent)
              VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "Untitled event").font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text(event.startDate, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                  .font(.system(size: 9)).foregroundStyle(.secondary)
              }
              Spacer()
              if let url = event.url {
                Button("Open") { NSWorkspace.shared.open(url) }.buttonStyle(.bordered)
              }
            }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
          }
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var calculatorResult: String? {
    var parser = NotchCalculator(calculation)
    guard let result = parser.evaluate() else { return nil }
    return String(format: "%.10g", result)
  }

  private var calculatorView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          TextField("e.g. (24 + 8) / 2", text: $calculation)
            .textFieldStyle(.roundedBorder).font(.system(size: 16, design: .monospaced))
            .focused($calculationFocused)
            .onSubmit { evaluateCalculation() }
            .accessibilityLabel("Expression")
          Button(scientific ? "Basic" : "Scientific") { scientific.toggle() }
        }
        HStack {
          Text(calculatorResult ?? "—")
            .font(.system(size: 22, weight: .semibold, design: .monospaced)).textSelection(.enabled)
            .accessibilityLabel("Result " + (calculatorResult ?? "unavailable"))
          Spacer()
          NotchActionButton(title: "Copy", symbol: "doc.on.doc", tint: skin.palette.accent) {
            guard let answer = calculatorResult else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(answer, forType: .string)
          }.disabled(calculatorResult == nil)
        }
        let keys = ["AC", "(", ")", "÷", "7", "8", "9", "×", "4", "5", "6", "−",
                    "1", "2", "3", "+", "0", ".", "%", "="]
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4), spacing: 4) {
          if scientific {
            ForEach(["sin(", "cos(", "tan(", "sqrt(", "log(", "ln(", "π", "^"], id: \.self) { key in
              calculationButton(key)
            }
          }
          ForEach(keys, id: \.self) { key in calculationButton(key) }
        }
      }.padding(7)
    }
    .onAppear { if !shelf.isArrowPreview { calculationFocused = true } }
    .onChange(of: shelf.isArrowPreview) { _, preview in if !preview { calculationFocused = true } }
    .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: scientific)
  }

  private func evaluateCalculation() {
    var parser = NotchCalculator(calculation)
    if let answer = parser.evaluate() { calculation = String(answer) }
  }

  private func calculationButton(_ key: String) -> some View {
    Button {
      switch key {
      case "AC": calculation = ""
      case "=": evaluateCalculation()
      default: calculation += key
      }
    } label: {
      Text(key).font(.system(.callout, design: .monospaced)).frame(maxWidth: .infinity).frame(height: 23)
    }.buttonStyle(.bordered)
  }

  private var screenshotView: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(tools.captures.count == 1 ? "1 region" : "\(tools.captures.count) regions").font(.headline)
        Spacer()
        Menu("Capture") {
          ForEach(WorkspaceCaptureMode.allCases) { mode in
            Button(mode.rawValue) { tools.captureWorkspace(mode) }
          }
        }.fixedSize()
        Button("Add region", action: tools.captureAnother)
      }
      HStack {
        Picker("Layout", selection: $tools.captureColumns) {
          Text("Stack").tag(1)
          Text("Grid").tag(2)
        }.pickerStyle(.segmented).labelsHidden().frame(width: 117)
        Spacer()
        Button("Copy joined", action: tools.copyCombinedCaptures).disabled(tools.captures.isEmpty)
        Button("Save PNG…", action: tools.saveCombinedCaptures).disabled(tools.captures.isEmpty)
        Button("Clear", action: tools.clearCaptures).disabled(tools.captures.isEmpty)
      }
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(Array(tools.captures.enumerated()), id: \.offset) { index, capture in
            VStack(spacing: 4) {
              Image(nsImage: capture).resizable().scaledToFit().frame(width: 100, height: 70)
              HStack {
                Button { tools.moveCapture(index, by: -1) } label: { Image(systemName: "arrow.left") }
                  .accessibilityLabel("Move region \(index + 1) earlier").disabled(index == 0)
                Button { tools.removeCapture(index) } label: { Image(systemName: "xmark") }
                  .accessibilityLabel("Remove region \(index + 1)")
                Button { tools.moveCapture(index, by: 1) } label: { Image(systemName: "arrow.right") }
                  .accessibilityLabel("Move region \(index + 1) later").disabled(index == tools.captures.count - 1)
              }.buttonStyle(.borderless)
            }.padding(5).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
          }
        }
      }
      Button("Search with Lens", action: tools.captureForLens).buttonStyle(.borderless)
        .help("Copies the selected area, then opens Google Lens for you to paste it")
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var systemView: some View {
    let info = ProcessInfo.processInfo
    return VStack(spacing: 8) {
      HStack(spacing: 10) {
        metric("Memory", ByteCountFormatter.string(fromByteCount: Int64(info.physicalMemory), countStyle: .memory), "memorychip")
        metric("Cores", "\(info.activeProcessorCount)", "cpu")
        metric("Uptime", uptime(info.systemUptime), "clock.arrow.circlepath")
      }
      HStack(spacing: 7) {
        metric("CPU use", macReadings?.cpu ?? "…", "cpu")
        metric("Active + wired + compressed", macReadings?.memory ?? "…", "memorychip")
        metric("Disk available", macReadings?.availableDisk ?? "…", "internaldrive")
      }
      Text(macReadings?.network ?? "Sampling network…").font(.caption).monospacedDigit()
      Button("Show Skippy notifications") {
        Task {
          let alerts = await UNUserNotificationCenter.current().deliveredNotifications()
          deliveredAlerts = alerts.isEmpty ? "No delivered Skippy alerts." : alerts.map { $0.request.content.title }.joined(separator: " · ")
        }
      }
      if !deliveredAlerts.isEmpty { Text(deliveredAlerts).font(.caption).lineLimit(2) }
      HStack { NotchSectionTitle(title: "Recent Skippy activity", symbol: "clock.arrow.circlepath"); Text(info.operatingSystemVersionString).font(.system(size: 8)).foregroundStyle(.secondary) }
      if recent.actions.isEmpty { Text("Your recent conversions, copies and packs appear here.").font(.system(size: 9)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
      else {
        ForEach(recent.actions.prefix(3)) { action in
          Label(action.title, systemImage: action.symbol).font(.system(size: 9.5, weight: .medium))
            .padding(.horizontal, 9).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        }
      }
    }
  }

  private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
    VStack(spacing: 5) {
      Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(skin.palette.accent)
      Text(value).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
      Text(title.uppercased()).font(.system(size: 7.5, weight: .bold)).tracking(0.5).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity).padding(9)
      .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func quickTile(_ module: NotchModule, detail: String) -> some View {
    Button { shelf.showModule(module) } label: {
      VStack(alignment: .leading, spacing: 6) {
        Image(systemName: module.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(skin.palette.accent)
        Spacer(minLength: 0)
        Text(module.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
        Text(detail).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
      }.padding(9).frame(maxWidth: .infinity, minHeight: 75, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.75))
    }.buttonStyle(.plain)
  }

  private func suggestion(_ text: String) -> some View {
    Button(text) { webQuery = text; tools.searchGoogle(text) }
      .buttonStyle(.plain).font(.system(size: 8.5, weight: .medium)).foregroundStyle(.secondary)
      .padding(.horizontal, 9).frame(height: 24).background(Color.primary.opacity(0.05), in: Capsule())
  }

  private func mediaButton(_ symbol: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: prominent ? 13 : 10, weight: .bold))
        .foregroundStyle(prominent ? skin.palette.paper : skin.palette.text)
        .frame(width: prominent ? 38 : 30, height: prominent ? 38 : 30)
        .background(prominent ? skin.palette.accent : Color.primary.opacity(0.06), in: Circle())
    }.buttonStyle(.plain)
  }

  private func uptime(_ seconds: TimeInterval) -> String {
    let hours = Int(seconds) / 3600
    return hours >= 24 ? "\(hours / 24)d" : "\(hours)h"
  }
}

private extension NSColor {
  convenience init?(hex: String) {
    let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard value.count == 6, let number = Int(value, radix: 16) else { return nil }
    self.init(srgbRed: CGFloat((number >> 16) & 0xff) / 255,
      green: CGFloat((number >> 8) & 0xff) / 255, blue: CGFloat(number & 0xff) / 255, alpha: 1)
  }
}

/// Type a tool name, move through matching tools with the arrow keys, and press Return.
private struct ArrowFinder: View {
  @ObservedObject var shelf: DropPopupController
  @ObservedObject private var tools = NotchToolStore.shared
  @ObservedObject private var quickPins = QuickPinStore.shared
  @ObservedObject private var shortcuts = GlobalShortcutManager.shared

  private enum Entry: Identifiable {
    case tool(NotchModule), app(PinnedNotchApp)
    var id: String {
      switch self { case .tool(let module): module.id; case .app(let app): app.id }
    }
    var title: String {
      switch self { case .tool(let module): module.title; case .app(let app): app.name }
    }
  }

  private var matches: [Entry] {
    let entries = NotchModule.allCases.filter { $0 != .dashboard }.map(Entry.tool) + tools.pinnedApps.map(Entry.app)
    let pinned = quickPins.pins.compactMap { pin in entries.first { $0.id == pin.id } }
    let query = shelf.arrowQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    if !query.isEmpty { return entries.filter { $0.title.localizedCaseInsensitiveContains(query) } }
    return pinned + entries.filter { !quickPins.contains($0.id) }
  }

  var body: some View {
    VStack(spacing: 8) {
      ArrowSearchField(query: $shelf.arrowQuery, focusRequest: shelf.arrowFocusRequest, move: { step in
        shelf.arrowIndex = min(max(0, shelf.arrowIndex + step), max(0, matches.count - 1))
      }, submit: {
        if matches.indices.contains(shelf.arrowIndex) { select(matches[shelf.arrowIndex]) }
      }, cancel: shelf.cancelChoosingArrow)
      .frame(height: 28)
      if matches.isEmpty {
        Text("No matching arrows").foregroundStyle(.secondary)
        Spacer()
      } else {
        ScrollViewReader { scroll in
          ScrollView {
            LazyVStack(spacing: 3) {
              ForEach(Array(matches.enumerated()), id: \.element.id) { position, entry in
                HStack(spacing: 5) {
                  Button { select(entry) } label: {
                    HStack {
                      switch entry {
                      case .tool(let module):
                        Image(systemName: module.symbol).frame(width: 22)
                      case .app(let app):
                        Image(nsImage: tools.icon(for: app)).resizable().scaledToFit().frame(width: 22, height: 17)
                      }
                      Text(entry.title)
                      Spacer()
                      if case .tool(let module) = entry {
                        Text(shortcuts.binding(for: .arrow(module)).displayName).font(.caption.monospaced())
                          .foregroundStyle(.secondary)
                      }
                    }.padding(.leading, 8).frame(height: 30).contentShape(Rectangle())
                  }.buttonStyle(.plain)
                  let pinned = quickPins.contains(entry.id)
                  Button { quickPins.toggle(entry.id) } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin").frame(width: 28, height: 28)
                  }.buttonStyle(.borderless)
                    .help(pinned ? "Remove Quick Pin" : "Add Quick Pin")
                    .accessibilityLabel((pinned ? "Unpin " : "Pin ") + entry.title)
                }.background(shelf.arrowIndex == position ? Color.primary.opacity(0.1) : .clear,
                  in: RoundedRectangle(cornerRadius: 6)).id(entry.id)
              }
            }
          }
          .onChange(of: shelf.arrowIndex, initial: true) { _, i in
            if matches.indices.contains(i) { scroll.scrollTo(matches[i].id) }
          }
        }
      }
    }
    .onChange(of: shelf.arrowQuery) { _, _ in shelf.arrowIndex = 0 }
    .onChange(of: matches.map(\.id)) { _, ids in
      if !ids.indices.contains(shelf.arrowIndex) { shelf.arrowIndex = 0 }
    }
  }

  private func select(_ entry: Entry) {
    switch entry {
    case .tool(let module): shelf.openArrow(module, at: SkippyQuiver.shared.anchor)
    case .app(let app): shelf.dismiss(); tools.launch(app)
    }
  }
}

private struct ArrowSearchField: NSViewRepresentable {
  @Binding var query: String
  let focusRequest: Int
  var move: (Int) -> Void
  var submit: () -> Void
  var cancel: () -> Void

  final class Field: NSSearchField {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard window != nil else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self, let window = self.window else { return }
        window.makeFirstResponder(self)
      }
    }
  }

  final class Coordinator: NSObject, NSSearchFieldDelegate {
    var parent: ArrowSearchField
    var lastFocusRequest: Int?
    init(_ parent: ArrowSearchField) { self.parent = parent }
    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSSearchField else { return }
      parent.query = field.stringValue
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
      switch command {
      case #selector(NSResponder.moveDown(_:)): parent.move(1)
      case #selector(NSResponder.moveUp(_:)): parent.move(-1)
      case #selector(NSResponder.insertNewline(_:)): parent.submit()
      case #selector(NSResponder.cancelOperation(_:)): parent.cancel()
      default: return false
      }
      return true
    }
  }
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> Field {
    let field = Field()
    field.placeholderString = "Find an arrow"
    field.setAccessibilityLabel("Find an arrow")
    field.delegate = context.coordinator
    return field
  }
  func updateNSView(_ field: Field, context: Context) {
    context.coordinator.parent = self
    if field.stringValue != query { field.stringValue = query }
    if context.coordinator.lastFocusRequest != focusRequest {
      context.coordinator.lastFocusRequest = focusRequest
      DispatchQueue.main.async { [weak field] in
        guard let field, let window = field.window, window.isVisible else { return }
        window.makeFirstResponder(field)
      }
    }
  }
}

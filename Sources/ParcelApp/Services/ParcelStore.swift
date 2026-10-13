import AppKit
import Combine
import Foundation
import ParcelCore
import UniformTypeIdentifiers

enum ParcelPhase: Equatable { case open, receiving, preparing, packing, ready }
@MainActor final class ParcelStore: ObservableObject {
  @Published var boxes: [ParcelBox] = []
  @Published var selectedBox: UUID?
  @Published var selectedItems: Set<UUID> = []
  @Published var phase: ParcelPhase = .open
  @Published var progress: Double = 0
  @Published var progressLabel = ""
  @Published var notice: String?
  @Published var error: String?
  @Published var bounce = 0
  @Published var showPrepare = false
  @Published var showRenameBox = false
  @Published var showWelcome = false
  @Published var recipe = ImageRecipe()
  @Published var packaging = PackagingOptions.load()
  @Published var archiveURL: URL?
  @Published var lastManifest = ""
  @Published var preferences = AppPreferences.load()
  @Published var license = LicenseStatus.development
  private let access = SourceAccess()
  private var token: CancellationToken?
  private var job: Task<Void, Never>?
  @Published var installingTool: PackFormat?
  private var libraryWritable = true
  private var receivingCount = 0
  private var cleanupChecked = false
  var busy: Bool { phase == .packing || phase == .preparing }
  var current: ParcelBox? { boxes.first { $0.id == selectedBox } }
  var items: [ParcelItem] { current?.items ?? [] }
  @Published var searchText = ""
  var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  /// Parcels whose name matches, or that contain a matching file.
  var filteredBoxes: [ParcelBox] {
    guard isSearching else { return boxes }
    let q = searchText.lowercased()
    return boxes.filter { box in
      box.name.lowercased().contains(q)
        || box.items.contains {
          $0.displayName.lowercased().contains(q) || $0.effectiveName.lowercased().contains(q)
        }
    }
  }
  /// Files in the current parcel matching the search.
  var filteredItems: [ParcelItem] {
    guard isSearching else { return items }
    let q = searchText.lowercased()
    return items.filter {
      $0.displayName.lowercased().contains(q) || $0.effectiveName.lowercased().contains(q)
    }
  }
  var workingItems: [ParcelItem] {
    selectedItems.isEmpty ? items : items.filter { selectedItems.contains($0.id) }
  }
  var imageItems: [ParcelItem] {
    workingItems.filter { ImagePipeline.canPrepare($0.sourceURL) && !$0.isDirectory }
  }
  var canExport: Bool { license.canUseApp }
  var ready: Bool {
    phase == .ready && archiveURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
  }

  init() {
    do {
      try StoragePaths.createDirectories()
      if FileManager.default.fileExists(atPath: StoragePaths.library.path) {
        let doc = try CollectionStore.read(from: StoragePaths.library)
        boxes = doc.boxes
        selectedBox = doc.selectedBox
        for b in boxes {
          for item in b.items { access.retain(access.resolve(item)) }
        }
        for bi in boxes.indices {
          for ii in boxes[bi].items.indices {
            let resolved = access.resolve(boxes[bi].items[ii])
            boxes[bi].items[ii].sourcePath = resolved.path
            if let prepared = boxes[bi].items[ii].preparedPath,
              !FileTree.isInside(URL(fileURLWithPath: prepared), directory: StoragePaths.prepared)
            {
              boxes[bi].items[ii].preparedPath = nil
              boxes[bi].items[ii].preparedBytes = nil
              boxes[bi].items[ii].preparedDescription = nil
            }
          }
        }
      }
    } catch {
      libraryWritable = false
      self.error =
        "Your saved parcel library could not be read. It has not been overwritten. \(error.localizedDescription)"
    }
    if boxes.isEmpty { boxes = [ParcelBox(name: "My first parcel")] }
    if !boxes.contains(where: { $0.id == selectedBox }) { selectedBox = boxes.first?.id }
    packaging.cleanMacMetadata = preferences.cleanMetadata
    packaging.includeManifest = preferences.includeManifest
    packaging.appendDate = preferences.appendDate
    showWelcome = !UserDefaults.standard.bool(forKey: "hasSeenWelcome")
    refreshLicense()
    restoreReadyState()
  }
  func cleanUnusedCopies() {
    guard !busy, libraryWritable else { return }
    do {
      let n = try CacheCare.removeUnused(boxes: boxes, olderThan: Date().addingTimeInterval(-86400))
      notice = "Removed \(n) unused app copies older than a day. Your originals are safe."
    } catch { self.error = error.localizedDescription }
  }
  func checkCacheOnStartup() {
    guard !cleanupChecked, libraryWritable else { return }
    cleanupChecked = true
    _ = try? CacheCare.removeUnused(boxes: boxes, olderThan: Date().addingTimeInterval(-30 * 86400))
  }
  func refreshLicense() { license = LicenseManager.shared.status() }
  /// Installs the 7-Zip / RAR tool via Homebrew, right from the app.
  func installArchiverTool(_ format: PackFormat) {
    guard installingTool == nil, format != .zip else { return }
    installingTool = format
    Task {
      do {
        try await Task.detached(priority: .userInitiated) {
          try ExternalArchiver.installTool(for: format)
        }.value
        installingTool = nil
        notice = "\(format.label) is installed — pack away."
      } catch {
        installingTool = nil
        self.error = error.localizedDescription
      }
    }
  }
  func savePackaging() { packaging.save() }
  func savePreferences() {
    preferences.save()
    var next = packaging
    next.cleanMacMetadata = preferences.cleanMetadata
    next.includeManifest = preferences.includeManifest
    next.appendDate = preferences.appendDate
    if packaging != next {
      packaging = next
      invalidateArchive()
    }
  }
  func save() {
    guard libraryWritable else { return }
    do {
      try CollectionStore.save(
        .init(boxes: boxes, selectedBox: selectedBox), to: StoragePaths.library)
    } catch { self.error = "This change could not be saved: \(error.localizedDescription)" }
  }
  func finishWelcome() {
    showWelcome = false
    UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
  }
  func selectBox(_ id: UUID) {
    guard !busy, receivingCount == 0 else { return }
    selectedBox = id
    selectedItems = []
    restoreReadyState()
    save()
  }
  func newBox() {
    guard !busy, receivingCount == 0 else { return }
    let box = ParcelBox(name: "Untitled parcel")
    boxes.insert(box, at: 0)
    selectedBox = box.id
    selectedItems = []
    invalidateArchive()
    save()
    showRenameBox = true
  }
  func renameBox(_ name: String) {
    guard !busy, let i = index else { return }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 80 else {
      error = "Use a parcel name between 1 and 80 characters."
      return
    }
    boxes[i].name = trimmed
    changed()
  }
  func deleteCurrentBox() {
    guard !busy, receivingCount == 0, let i = index else { return }
    boxes.remove(at: i)
    if boxes.isEmpty { boxes = [ParcelBox(name: "My parcel")] }
    selectedBox = boxes.first?.id
    selectedItems = []
    restoreReadyState()
    reconcileAccess()
    save()
  }
  private var index: Int? { boxes.firstIndex { $0.id == selectedBox } }
  private func changed() {
    if let i = index {
      boxes[i].updatedAt = Date()
      boxes[i].lastArchivePath = nil
    }
    invalidateArchive()
    save()
  }
  func invalidateArchive() {
    archiveURL = nil
    lastManifest = ""
    if !busy { phase = .open }
    progress = 0
  }
  private func restoreReadyState() {
    // Reopening a collection always requires resealing: sources may have changed externally.
    archiveURL = nil
    phase = .open
    lastManifest = ""  // Rebuilt when copied, so a stale manifest is never shown.
  }
  private func reconcileAccess() { access.reconcile(Set(boxes.flatMap(\.items).map(\.sourcePath))) }
  func updateNote(_ note: String) {
    guard !busy, let i = index else { return }
    boxes[i].note = String(note.prefix(2000))
    changed()
  }
  func addFilesPanel() {
    guard !busy else { return }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = true
    panel.prompt = "Add to parcel"
    panel.message = "Choose the pieces you'd like to send together."
    if panel.runModal() == .OK { ingest(panel.urls) }
  }
  func beginReceiving() {
    receivingCount += 1
    if !busy { phase = .receiving }
  }
  func endReceiving() {
    receivingCount = max(0, receivingCount - 1)
    if receivingCount == 0 && phase == .receiving { phase = .open }
  }
  func ingest(_ urls: [URL], into id: UUID? = nil) {
    guard !busy, let boxID = id ?? selectedBox else { return }
    var rejected: [String] = []
    for url in urls {
      do {
        guard url.isFileURL else { throw ParcelError.unsupportedSource("This content") }
        access.retain(url)
        let values = try url.resourceValues(forKeys: [.isAliasFileKey])
        guard values.isAliasFile != true else {
          throw ParcelError.unsupportedSource(url.lastPathComponent)
        }
        let info = try FileTree.inspect(url)
        guard let bi = boxes.firstIndex(where: { $0.id == boxID }) else { return }
        let path = url.standardizedFileURL.path
        guard !boxes[bi].items.contains(where: { $0.sourcePath == path }) else { continue }
        guard boxes[bi].items.count < 2000 else {
          throw ParcelError.storageError("A parcel can contain up to 2,000 top-level items.")
        }
        boxes[bi].items.append(
          ParcelItem(
            sourcePath: path, bookmark: access.bookmark(url), displayName: url.lastPathComponent,
            isDirectory: info.folder, byteCount: info.folder ? 0 : info.bytes))
        boxes[bi].updatedAt = Date()
        boxes[bi].lastArchivePath = nil
        bounce += 1
      } catch { rejected.append(error.localizedDescription) }
    }
    invalidateArchive()
    save()
    reconcileAccess()
    if !rejected.isEmpty { error = rejected.joined(separator: "\n") }
  }
  func paste() {
    guard !busy else { return }
    if let urls = NSPasteboard.general.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty
    {
      ingest(urls)
      return
    }
    guard let image = NSImage(pasteboard: NSPasteboard.general),
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
    else {
      if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
        ingestText(text)
      } else {
        notice = "Copy files, an image, a link or some words, then paste them into your parcel."
      }
      return
    }
    do {
      let url = StoragePaths.received.appendingPathComponent(
        "Pasted image-" + UUID().uuidString + ".png")
      try png.write(to: url, options: .atomic)
      ingest([url])
    } catch { self.error = error.localizedDescription }
  }
  func ingestText(_ text: String, into boxID: UUID? = nil) {
    guard !busy else { return }
    guard text.utf8.count <= 8 * 1024 * 1024 else {
      error = "This text is too large for a clipboard piece. Save it as a file, then add the file."
      return
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let link = URL(string: trimmed)
    let isLink =
      link?.host != nil && ["http", "https"].contains(link?.scheme?.lowercased() ?? "")
      && !trimmed.contains("\n")
    let name = isLink ? "Reference — \(link?.host ?? "link").txt" : "Copied words.txt"
    do {
      let folder = StoragePaths.received.appendingPathComponent(
        UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let output = folder.appendingPathComponent(name)
      try text.write(to: output, atomically: true, encoding: .utf8)
      ingest([output], into: boxID)
      if isLink {
        notice = "Link saved as readable text. Access permissions on the linked page are unchanged."
      }
    } catch { self.error = error.localizedDescription }
  }
  func toggleSelection(_ id: UUID) {
    if selectedItems.contains(id) { selectedItems.remove(id) } else { selectedItems.insert(id) }
  }
  func selectAll() { selectedItems = Set(items.map(\.id)) }
  func remove(_ ids: Set<UUID>) {
    guard !busy, let i = index else { return }
    boxes[i].items.removeAll { ids.contains($0.id) }
    selectedItems.subtract(ids)
    changed()
    reconcileAccess()
  }
  func renameItem(_ id: UUID, name: String) {
    guard !busy, let i = index, let j = boxes[i].items.firstIndex(where: { $0.id == id }) else {
      return
    }
    do {
      boxes[i].items[j].displayName = try NamePolicy.validate(name)
      changed()
    } catch { self.error = error.localizedDescription }
  }
  func reorder(_ id: UUID, before target: UUID) {
    guard !busy, let i = index, let source = boxes[i].items.firstIndex(where: { $0.id == id }),
      id != target
    else { return }
    let item = boxes[i].items.remove(at: source)
    if let destination = boxes[i].items.firstIndex(where: { $0.id == target }) {
      boxes[i].items.insert(item, at: destination)
    } else {
      boxes[i].items.append(item)
    }
    changed()
  }
  func restoreOriginals() {
    guard !busy, let i = index else { return }
    let ids = Set(workingItems.map(\.id))
    for j in boxes[i].items.indices where ids.contains(boxes[i].items[j].id) {
      boxes[i].items[j].preparedPath = nil
      boxes[i].items[j].preparedBytes = nil
      boxes[i].items[j].preparedDescription = nil
    }
    changed()
    notice = "Originals are selected again. Your prepared copies remain in the local cache."
  }
  func locate(_ item: ParcelItem) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = item.isDirectory
    panel.canChooseFiles = !item.isDirectory
    panel.prompt = "Locate original"
    if panel.runModal() == .OK, let url = panel.url, let i = index,
      let j = boxes[i].items.firstIndex(where: { $0.id == item.id })
    {
      do {
        access.retain(url)
        guard try url.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile != true else {
          throw ParcelError.unsupportedSource(url.lastPathComponent)
        }
        let info = try FileTree.inspect(url)
        boxes[i].items[j].sourcePath = url.path
        boxes[i].items[j].bookmark = access.bookmark(url)
        boxes[i].items[j].isDirectory = info.folder
        boxes[i].items[j].byteCount = info.folder ? 0 : info.bytes
        boxes[i].items[j].preparedPath = nil
        boxes[i].items[j].preparedBytes = nil
        boxes[i].items[j].preparedDescription = nil
        changed()
      } catch { self.error = error.localizedDescription }
      reconcileAccess()
    }
  }
  func prepareImages() {
    refreshLicense()
    // Every refusal explains itself — a dead button with no feedback is a bug.
    guard canExport else {
      error = "Preparing images needs an active licence. Your trial may have ended."
      return
    }
    guard !busy else {
      notice = "Hold on — your parcel is still packing. Try again in a moment."
      return
    }
    guard receivingCount == 0 else {
      notice = "Still receiving your files — one moment."
      return
    }
    guard !imageItems.isEmpty, let boxID = selectedBox else { return }
    let targets = imageItems
    let settings = recipe
    let t = CancellationToken()
    token = t
    phase = .preparing
    progress = 0
    showPrepare = false
    job = Task {
      var results: [(UUID, PreparedImage)] = []
      var failures: [String] = []
      for (idx, item) in targets.enumerated() {
        if t.isCancelled { break }
        progress = Double(idx) / Double(targets.count)
        progressLabel = "Preparing \(item.displayName)"
        do {
          let result = try await Task.detached(priority: .userInitiated) {
            try ImagePipeline.prepare(
              source: item.sourceURL, recipe: settings, token: t, outputName: item.displayName)
          }.value
          results.append((item.id, result))
        } catch { if !t.isCancelled { failures.append(error.localizedDescription) } }
      }
      if t.isCancelled {
        for (_, r) in results { StoragePaths.deleteOwned(r.url) }
        notice = "Preparation cancelled. Originals are unchanged."
      } else if let bi = boxes.firstIndex(where: { $0.id == boxID }) {
        for (id, r) in results {
          if let j = boxes[bi].items.firstIndex(where: { $0.id == id }) {
            boxes[bi].items[j].preparedPath = r.url.path
            boxes[bi].items[j].preparedBytes = r.bytes
            boxes[bi].items[j].preparedDescription = r.description
          }
        }
        boxes[bi].lastArchivePath = nil
        boxes[bi].updatedAt = Date()
        notice =
          "\(results.count) prepared \(results.count == 1 ? "copy" : "copies"). Originals are safe."
      }
      phase = .open
      token = nil
      job = nil
      archiveURL = nil
      progress = 0
      save()
      if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }
  }
  func seal() {
    refreshLicense()
    guard !busy, receivingCount == 0, canExport, let box = current, !box.items.isEmpty else {
      return
    }
    guard box.items.allSatisfy({ FileManager.default.fileExists(atPath: $0.effectiveURL.path) })
    else {
      error =
        "A parcel item is missing. Locate it, restore its original, or remove it before sealing."
      return
    }
    let options = packaging
    let t = CancellationToken()
    let boxID = box.id
    let ext = options.format.fileExtension
    let title = NamePolicy.safeArchiveStem(box.name, date: options.appendDate ? Date() : nil)
    // Desktop parcels land on the Desktop itself; otherwise they stage in
    // Parcel's own folder until saved elsewhere.
    let folder = StoragePaths.exports.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let desktopURL =
      options.saveToDesktop
      ? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first : nil
    if desktopURL == nil {
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      } catch {
        self.error = error.localizedDescription
        return
      }
    }
    let output: URL
    if let desktopURL {
      output = uniqueURL(desktopURL.appendingPathComponent(title + "." + ext))
    } else {
      output = folder.appendingPathComponent(title + "." + ext)
    }
    let inputs = box.items.map {
      PackageInput(url: $0.effectiveURL, desiredName: $0.effectiveName, originalBytes: $0.byteCount)
    }
    token = t
    phase = .packing
    progress = 0
    archiveURL = nil
    progressLabel = "Gathering your pieces"
    job = Task {
      do {
        let result = try await Task.detached(priority: .userInitiated) {
          try PackageBuilder.build(
            inputs: inputs, title: box.name, note: box.note, destination: output, options: options,
            token: t,
            copySource: { source, destination, clean, token in
              try CoordinatedFiles.read(source) { actual in
                try FileTree.copy(actual, to: destination, cleanMetadata: clean, token: token)
              }
            }
          ) { fraction, label in
            Task { @MainActor [weak self] in
              if self?.token === t {
                self?.progress = fraction
                self?.progressLabel = label
              }
            }
          }
        }.value
        if let i = boxes.firstIndex(where: { $0.id == boxID }) {
          boxes[i].lastArchivePath = result.archive.path
        }
        archiveURL = result.archive
        lastManifest = result.manifestText
        phase = .ready
        progress = 1
        // The packed file wears Parcel's icon on the Desktop and in Finder.
        if let icon = NSApp.applicationIconImage {
          NSWorkspace.shared.setIcon(icon, forFile: result.archive.path, options: [])
        }
        notice =
          options.saveToDesktop
          ? "Packed and saved to your Desktop."
          : "Packed. Ready to drag or share."
        save()
        if preferences.playSounds { FeedbackSounds.shared.seal() }
      } catch {
        StoragePaths.deleteOwned(folder)
        phase = .open
        progress = 0
        if t.isCancelled {
          notice = "Cancelled. Originals are unchanged."
        } else {
          self.error = error.localizedDescription
        }
      }
      token = nil
      job = nil
    }
  }
  func cancel() {
    token?.cancel()
    progressLabel = "Finishing the current operation safely…"
  }
  func unseal() {
    guard !busy else { return }
    phase = .open
    bounce += 1
  }
  func markReady() { if archiveURL != nil { phase = .ready } }
  func copyManifest() {
    guard let box = current else { return }
    var used: Set<String> = packaging.includeManifest ? [NamePolicy.key("Parcel contents.txt")] : []
    do {
      let entries = try box.items.map { item in
        ManifestEntry(
          name: try NamePolicy.unique(item.effectiveName, used: &used), bytes: item.effectiveBytes,
          folder: item.isDirectory)
      }
      let text =
        lastManifest.isEmpty
        ? PackageBuilder.manifest(title: box.name, note: box.note, entries: entries, date: Date())
        : lastManifest
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
      Toaster.shared.copied("Contents list")
      notice = "Contents list copied."
    } catch { self.error = error.localizedDescription }
  }
  /// Saves the packed parcel straight to the default location — no questions.
  /// Change the location in Preferences.
  func saveArchive() {
    guard ready, let source = archiveURL else { return }
    let dir: URL
    if let path = preferences.exportFolder, FileManager.default.fileExists(atPath: path) {
      dir = URL(fileURLWithPath: path)
    } else if let downloads = FileManager.default.urls(
      for: .downloadsDirectory, in: .userDomainMask).first
    {
      dir = downloads
    } else {
      self.error = "Could not find your Downloads folder."
      return
    }
    let destination = uniqueURL(dir.appendingPathComponent(source.lastPathComponent))
    do {
      try FileManager.default.copyItem(at: source, to: destination)
      preferences.exportFolder = dir.path
      preferences.save()
      Toaster.shared.note("Saved to \(dir.lastPathComponent)")
      notice = "Saved \(destination.lastPathComponent) to \(dir.lastPathComponent)."
    } catch { self.error = error.localizedDescription }
  }
  func revealArchive() {
    if let archiveURL { NSWorkspace.shared.activateFileViewerSelecting([archiveURL]) }
  }
  /// Edge shelf: a brand-new parcel gathered from these files. Packing stays a
  /// deliberate one-click step, so drops never collide with a running pack.
  func dropToNewParcel(_ urls: [URL]) {
    guard !busy, !urls.isEmpty else { return }
    let nb = ParcelBox(name: "Untitled parcel")
    boxes.insert(nb, at: 0)
    selectedBox = nb.id
    selectedItems = []
    invalidateArchive()
    save()
    ingest(urls)
    notice = "New parcel started — press Pack ZIP when ready."
  }
  /// Edge shelf: a brand-new parcel from dropped text.
  func dropTextToNewParcel(_ text: String) {
    guard !busy, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let nb = ParcelBox(name: "Untitled parcel")
    boxes.insert(nb, at: 0)
    selectedBox = nb.id
    selectedItems = []
    invalidateArchive()
    save()
    ingestText(text, into: nb.id)
  }
  /// A free filename next to the given URL ("Name 2.ext" when taken).
  private func uniqueURL(_ url: URL) -> URL {
    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path) else { return url }
    let stem = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension
    var i = 2
    while true {
      let candidate = url.deletingLastPathComponent().appendingPathComponent(
        "\(stem) \(i).\(ext)")
      if !fm.fileExists(atPath: candidate.path) { return candidate }
      i += 1
    }
  }
  func copyArchiveToClipboard() {
    guard canExport, !busy, ready, let zip = archiveURL else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.writeObjects([zip as NSURL])
    Toaster.shared.copied("Parcel \(zip.pathExtension.uppercased())")
    notice = "Parcel \(zip.pathExtension.uppercased()) copied — paste it anywhere."
  }
  /// A shareable file link to the packed parcel — paste it into any app on
  /// this Mac to hand the parcel over.
  func copyArchiveLink() {
    guard canExport, !busy, ready, let url = archiveURL else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(url.absoluteString, forType: .string)
    Toaster.shared.copied("Share link")
    notice = "Link copied — it opens this parcel on your Mac."
  }
  /// Parcels with a packed file on disk, newest first — for the menu bar.
  var recentParcels: [ParcelBox] {
    boxes.filter {
      guard let path = $0.lastArchivePath else { return false }
      return FileManager.default.fileExists(atPath: path)
    }
  }
  /// WhatsApp on macOS has no file-share API, so the packed parcel is copied
  /// and WhatsApp is brought forward — one paste drops it into any chat.
  func shareViaWhatsApp() {
    refreshLicense()
    guard canExport, !busy else { return }
    guard ready, let zip = archiveURL else {
      notice = "Pack your parcel first, then send it with WhatsApp."
      return
    }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.writeObjects([zip as NSURL])
    Toaster.shared.copied("Parcel \(zip.pathExtension.uppercased())")
    if let appURL = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: "net.whatsapp.WhatsApp")
    {
      let config = NSWorkspace.OpenConfiguration()
      config.activates = true
      NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in }
      notice = "Parcel copied — paste it into your WhatsApp chat."
    } else {
      revealArchive()
      notice =
        "WhatsApp isn't installed on this Mac. Your parcel is copied and shown in Finder — drag it into any chat."
    }
  }
  func shareItems() -> [Any] {
    guard canExport, !busy else { return [] }
    if ready, let archiveURL { return [archiveURL] }
    return workingItems.map(\.effectiveURL).filter {
      FileManager.default.fileExists(atPath: $0.path)
    }
  }
  func airDrop() {
    let urls = shareItems()
    guard !urls.isEmpty else { return }
    NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
  }
  func resetLibraryAfterBackup() {
    guard !libraryWritable else { return }
    do {
      let backup = StoragePaths.root.appendingPathComponent(
        "parcels-backup-" + UUID().uuidString + ".json")
      if FileManager.default.fileExists(atPath: StoragePaths.library.path) {
        try FileManager.default.copyItem(at: StoragePaths.library, to: backup)
      }
      try CollectionStore.save(
        .init(boxes: boxes, selectedBox: selectedBox), to: StoragePaths.library)
      libraryWritable = true
      error = nil
      notice = "The previous library was backed up before starting fresh."
    } catch { self.error = "Could not back up the library: \(error.localizedDescription)" }
  }
  var needsLibraryRecovery: Bool { !libraryWritable }
}

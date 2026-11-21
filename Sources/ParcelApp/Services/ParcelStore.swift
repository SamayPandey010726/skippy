import AppKit
import Combine
import Foundation
import ParcelCore
import UniformTypeIdentifiers

enum ParcelPhase: Equatable { case open, receiving, preparing, packing, ready }
@MainActor final class ParcelStore: ObservableObject {
  @Published var boxes: [ParcelBox] = []
  @Published private(set) var trashedBoxes: [TrashedParcel] = []
  @Published var showBin = false
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
  @Published var videoRecipe = VideoRecipe()
  @Published var showVideoPrepare = false
  @Published var showTransform = false
  @Published var packaging = PackagingOptions.load()
  @Published var archiveURL: URL?
  @Published var lastManifest = ""
  @Published var preferences = AppPreferences.load()
  @Published var license = LicenseStatus.development
  private let access = SourceAccess()
  private var token: CancellationToken?
  private var job: Task<Void, Never>?
  @Published var installingTool: PackFormat?
  @Published var extractingText = false
  private var libraryWritable = true
  private var receivingCount = 0
  private var cleanupChecked = false
  private var persistsLibrary = true
  private var binTimer: Timer?
  private var retainedBoxes: [ParcelBox] { boxes + trashedBoxes.map(\.box) }
  var busy: Bool { phase == .packing || phase == .preparing }
  var current: ParcelBox? { boxes.first { $0.id == selectedBox } }
  var items: [ParcelItem] { current?.items ?? [] }
  @Published var searchText = ""
  @Published var fileTypeFilter = FileSearchType.any
  @Published var fileSizeFilter = FileSearchSize.any
  @Published var fileAddedFilter = FileSearchAdded.anytime
  var isSearching: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fileTypeFilter != .any || fileSizeFilter != .any || fileAddedFilter != .anytime
  }
  var fileQuery: ParcelFileQuery { ParcelFileQuery(searchText, type: fileTypeFilter, size: fileSizeFilter, added: fileAddedFilter) }
  var rankedBoxes: [ParcelBox] { ShelfRanking.destinations(boxes, limit: boxes.count) }
  var filteredBoxes: [ParcelBox] {
    let ranked = rankedBoxes
    guard isSearching else { return ranked }
    let query = fileQuery
    return ranked.filter { box in
      (!searchText.isEmpty && fileTypeFilter == .any && fileSizeFilter == .any && fileAddedFilter == .anytime && box.name.localizedCaseInsensitiveContains(searchText))
        || box.items.contains(where: query.matches)
    }
  }
  func filteredItems(in box: ParcelBox) -> [ParcelItem] {
    guard isSearching else { return box.items }
    let query = fileQuery
    return box.items.filter(query.matches)
  }
  func compactItems(_ items: [ParcelItem]) -> [ParcelItem] {
    var seen: Set<UUID> = []
    return items.filter { item in
      guard let stackID = item.stackID else { return true }
      return seen.insert(stackID).inserted
    }
  }
  func stackMembers(of item: ParcelItem, in box: ParcelBox) -> [ParcelItem] {
    guard let stackID = item.stackID else { return [item] }
    return box.items.filter { $0.stackID == stackID }
  }
  func stackCount(of item: ParcelItem, in box: ParcelBox) -> Int { stackMembers(of: item, in: box).count }
  var filteredItems: [ParcelItem] { current.map(filteredItems(in:)) ?? [] }
  func clearFileSearch() {
    searchText = ""; fileTypeFilter = .any; fileSizeFilter = .any; fileAddedFilter = .anytime
  }
  var workingItems: [ParcelItem] {
    selectedItems.isEmpty ? items : items.filter { selectedItems.contains($0.id) }
  }
  var imageItems: [ParcelItem] {
    workingItems.filter { ImagePipeline.canPrepare($0.sourceURL) && !$0.isDirectory }
  }
  var videoItems: [ParcelItem] { workingItems.filter { !$0.isDirectory && VideoPipeline.canPrepare($0.sourceURL) } }
  var transformItems: [ParcelItem] {
    workingItems.filter { !$0.isDirectory && DocumentTransformPipeline.canTransform($0.effectiveURL) }
  }
  var availableTransforms: [DocumentTransformKind] {
    DocumentTransformPipeline.available(for: transformItems.map(\.effectiveURL))
  }
  var canExport: Bool { license.canUseApp }
  var ready: Bool {
    phase == .ready && archiveURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
  }

  init(persist: Bool = true) {
    persistsLibrary = persist
    if !persist {
      let box = ParcelBox(name: "My first parcel")
      boxes = [box]
      selectedBox = box.id
      return
    }
    do {
      try StoragePaths.createDirectories()
      if FileManager.default.fileExists(atPath: StoragePaths.library.path) {
        let doc = try CollectionStore.read(from: StoragePaths.library)
        boxes = doc.boxes
        trashedBoxes = doc.trashedBoxes
        selectedBox = doc.selectedBox
        boxes = boxes.map(resolvePersistedBox)
        trashedBoxes = trashedBoxes.map { entry in
          var next = entry
          next.box = resolvePersistedBox(entry.box)
          return next
        }
      }
    } catch {
      libraryWritable = false
      self.error =
        "Your saved parcel library could not be read. It has not been overwritten. \(error.localizedDescription)"
    }
    boxes = ShelfRanking.normalizePins(boxes)
    if boxes.isEmpty { boxes = [ParcelBox(name: "My first parcel")] }
    if !boxes.contains(where: { $0.id == selectedBox }) { selectedBox = boxes.first?.id }
    packaging.cleanMacMetadata = preferences.cleanMetadata
    packaging.includeManifest = preferences.includeManifest
    packaging.appendDate = preferences.appendDate
    showWelcome = !UserDefaults.standard.bool(forKey: "hasSeenWelcome")
    refreshLicense()
    restoreReadyState()
    purgeExpiredBin()
    scheduleBinExpiry()
  }
  private func resolvePersistedBox(_ box: ParcelBox) -> ParcelBox {
    var resolvedBox = box
    for position in resolvedBox.items.indices {
      let resolved = access.resolve(resolvedBox.items[position])
      access.retain(resolved)
      resolvedBox.items[position].sourcePath = resolved.path
      if let prepared = resolvedBox.items[position].preparedPath,
        !FileTree.isInside(URL(fileURLWithPath: prepared), directory: StoragePaths.prepared) {
        resolvedBox.items[position].preparedPath = nil
        resolvedBox.items[position].preparedBytes = nil
        resolvedBox.items[position].preparedDescription = nil
      }
    }
    return resolvedBox
  }
  func cleanUnusedCopies() {
    guard !busy, libraryWritable else { return }
    do {
      let n = try CacheCare.removeUnused(boxes: retainedBoxes, olderThan: Date().addingTimeInterval(-86400))
      notice = "Removed \(n) unused app copies older than a day. Your originals are safe."
    } catch { self.error = error.localizedDescription }
  }
  func checkCacheOnStartup() {
    guard !cleanupChecked, libraryWritable else { return }
    cleanupChecked = true
    _ = try? CacheCare.removeUnused(boxes: retainedBoxes, olderThan: Date().addingTimeInterval(-30 * 86400))
    if preferences.autoClearStale { clearStaleItems() }
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
    do {
      try persistLibrary()
    } catch { self.error = "This change could not be saved: \(error.localizedDescription)" }
  }
  private func persistLibrary() throws {
    guard libraryWritable, persistsLibrary else { return }
    try CollectionStore.save(
      .init(boxes: boxes, selectedBox: selectedBox, trashedBoxes: trashedBoxes), to: StoragePaths.library)
  }
  func finishWelcome() {
    showWelcome = false
    UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
  }
  func selectBox(_ id: UUID) {
    guard !busy, receivingCount == 0 else { return }
    guard boxes.contains(where: { $0.id == id }) else { return }
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
  @discardableResult func createNamedBox(_ name: String, pin: Bool = true) -> UUID? {
    guard !busy, receivingCount == 0, libraryWritable else { return nil }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 80 else {
      error = "Use a parcel name between 1 and 80 characters."
      return nil
    }
    var box = ParcelBox(name: trimmed)
    box.isPinned = pin
    if pin {
      for index in boxes.indices where boxes[index].isShelfPinned { boxes[index].isPinned = false }
    }
    boxes.insert(box, at: 0)
    selectedBox = box.id
    selectedItems = []
    invalidateArchive()
    save()
    return box.id
  }
  func shelfDestination(_ destination: UUID?) -> UUID? {
    guard !busy, receivingCount == 0, libraryWritable else { return nil }
    if let destination {
      guard boxes.contains(where: { $0.id == destination }) else { return nil }
      selectBox(destination)
      return destination
    }
    let box = ParcelBox(name: "Untitled parcel")
    boxes.insert(box, at: 0)
    selectedBox = box.id
    selectedItems = []
    invalidateArchive()
    save()
    return box.id
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
  func nameCurrentFromContents() {
    guard !busy, let suggestion = ParcelNameSuggester.suggest(for: items) else {
      notice = "Add a few files before asking Parcel for a name."
      return
    }
    renameBox(suggestion)
    notice = "Named locally from file metadata."
    RecentActionStore.shared.record(id: "smart-name", title: "Name from contents", symbol: "sparkles")
  }
  func toggleParcelPin(_ id: UUID) {
    guard !busy, receivingCount == 0, libraryWritable,
      let position = boxes.firstIndex(where: { $0.id == id }) else { return }
    let pinning = !boxes[position].isShelfPinned
    var next = boxes
    for candidate in next.indices {
      if candidate == position { next[candidate].isPinned = pinning }
      else if pinning && next[candidate].isShelfPinned { next[candidate].isPinned = false }
    }
    boxes = next
    save()
  }
  func shelfFileURLs(in boxID: UUID, itemID: UUID? = nil) throws -> [URL] {
    guard let box = boxes.first(where: { $0.id == boxID }) else {
      throw ParcelError.storageError("This parcel is no longer in your library.")
    }
    let pieces = itemID.map { target -> [ParcelItem] in
      guard let item = box.items.first(where: { $0.id == target }) else { return [] }
      return stackMembers(of: item, in: box)
    } ?? box.items
    guard !pieces.isEmpty else { throw ParcelError.emptyCollection }
    return try pieces.map { piece in
      let url = piece.effectiveURL
      guard FileManager.default.fileExists(atPath: url.path) else {
        throw ParcelError.missingSource(piece.effectiveName)
      }
      return url
    }
  }
  @discardableResult func copyShelfFiles(in boxID: UUID, itemID: UUID? = nil,
                                         to board: NSPasteboard = .general, matchingSearch: Bool = false) throws -> Int {
    guard canExport, !busy, receivingCount == 0 else {
      throw ParcelError.storageError("Copy is unavailable while packing or when a licence is required.")
    }
    let urls: [URL]
    if matchingSearch, itemID == nil, let box = boxes.first(where: { $0.id == boxID }) {
      let pieces = filteredItems(in: box)
      guard !pieces.isEmpty else { throw ParcelError.emptyCollection }
      urls = try pieces.map { piece in
        guard FileManager.default.fileExists(atPath: piece.effectiveURL.path) else { throw ParcelError.missingSource(piece.effectiveName) }
        return piece.effectiveURL
      }
    } else { urls = try shelfFileURLs(in: boxID, itemID: itemID) }
    board.clearContents()
    guard board.writeObjects(urls.map { $0 as NSURL }) else {
      throw ParcelError.storageError("The clipboard is unavailable. Drag the files out instead.")
    }
    return urls.count
  }
  func deleteCurrentBox() {
    if let selectedBox { moveToBin(selectedBox) }
  }
  func moveToBin(_ boxID: UUID, now: Date = Date()) {
    guard !busy, receivingCount == 0, libraryWritable,
      let position = boxes.firstIndex(where: { $0.id == boxID }) else { return }
    updateBin {
      let box = boxes.remove(at: position)
      trashedBoxes.insert(TrashedParcel(box: box, deletedAt: now), at: 0)
      if boxes.isEmpty { boxes = [ParcelBox(name: "My parcel")] }
      if selectedBox == boxID { selectedBox = boxes.first?.id }
    }
  }
  func restoreFromBin(_ boxID: UUID, now: Date = Date()) {
    guard !busy, receivingCount == 0, libraryWritable,
      let position = trashedBoxes.firstIndex(where: { $0.id == boxID }) else { return }
    guard trashedBoxes[position].expiresAt > now else { purgeExpiredBin(now: now); return }
    guard !boxes.contains(where: { $0.id == boxID }) else {
      error = "An active parcel already has this identity. The Bin entry has been kept unchanged."
      return
    }
    updateBin {
      var box = trashedBoxes.remove(at: position).box
      if box.isShelfPinned && boxes.contains(where: \.isShelfPinned) { box.isPinned = false }
      boxes.insert(box, at: 0)
      selectedBox = box.id
    }
  }
  func emptyBin(_ boxID: UUID? = nil) {
    guard !busy, receivingCount == 0, libraryWritable else { return }
    updateBin {
      if let boxID { trashedBoxes.removeAll { $0.id == boxID } }
      else { trashedBoxes.removeAll() }
    }
  }
  func purgeExpiredBin(now: Date = Date()) {
    guard !busy, receivingCount == 0, libraryWritable else { return }
    guard trashedBoxes.contains(where: { $0.expiresAt <= now }) else { return }
    updateBin { trashedBoxes.removeAll { $0.expiresAt <= now } }
  }
  private func updateBin(_ change: () -> Void) {
    let previousBoxes = boxes
    let previousBin = trashedBoxes
    let previousSelection = selectedBox
    change()
    do {
      try persistLibrary()
      if selectedBox != previousSelection {
        selectedItems = []
        restoreReadyState()
      }
      reconcileAccess()
      scheduleBinExpiry()
    } catch {
      boxes = previousBoxes
      trashedBoxes = previousBin
      selectedBox = previousSelection
      self.error = "The Bin could not be updated. Your parcels are unchanged. \(error.localizedDescription)"
    }
  }
  private func scheduleBinExpiry() {
    binTimer?.invalidate()
    guard persistsLibrary, let deadline = trashedBoxes.map(\.expiresAt).min() else { return }
    let timer = Timer(timeInterval: max(60, deadline.timeIntervalSinceNow), repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.purgeExpiredBin()
        self?.scheduleBinExpiry()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    binTimer = timer
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
  private func reconcileAccess() { access.reconcile(Set(retainedBoxes.flatMap(\.items).map(\.sourcePath))) }
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
    guard !busy, let boxID = id ?? selectedBox,
      let boxIndex = boxes.firstIndex(where: { $0.id == boxID }) else { return }
    var updatedBox = boxes[boxIndex]
    var knownPaths = Set(updatedBox.items.map(\.sourcePath))
    let originalCount = updatedBox.items.count
    var rejected: [String] = []
    for url in urls {
      do {
        guard url.isFileURL else { throw ParcelError.unsupportedSource("This content") }
        let path = url.standardizedFileURL.path
        guard !knownPaths.contains(path) else { continue }
        access.retain(url)
        let values = try url.resourceValues(forKeys: [.isAliasFileKey])
        guard values.isAliasFile != true else {
          throw ParcelError.unsupportedSource(url.lastPathComponent)
        }
        let info = try FileTree.inspect(url)
        guard updatedBox.items.count < 2000 else {
          throw ParcelError.storageError("A parcel can contain up to 2,000 top-level items.")
        }
        updatedBox.items.append(
          ParcelItem(
            sourcePath: path, bookmark: access.bookmark(url), displayName: url.lastPathComponent,
            isDirectory: info.folder, byteCount: info.folder ? 0 : info.bytes))
        knownPaths.insert(path)
      } catch { rejected.append(error.localizedDescription) }
    }
    if updatedBox.items.count != originalCount {
      updatedBox.updatedAt = Date()
      updatedBox.lastArchivePath = nil
      boxes[boxIndex] = updatedBox
      bounce += 1
    }
    if boxID == selectedBox { invalidateArchive() }
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
      let destination = boxID ?? selectedBox
      if let destination, let boxIndex = boxes.firstIndex(where: { $0.id == destination }),
        let itemIndex = boxes[boxIndex].items.firstIndex(where: { $0.sourcePath == output.path }) {
        boxes[boxIndex].items[itemIndex].inlineText = text
        save()
      }
      if isLink {
        notice = "Link saved as readable text. Access permissions on the linked page are unchanged."
      }
    } catch { self.error = error.localizedDescription }
  }
  func toggleSelection(_ id: UUID) {
    if selectedItems.contains(id) { selectedItems.remove(id) } else { selectedItems.insert(id) }
  }
  func stackSelected() {
    guard !busy, let index, selectedItems.count > 1 else { return }
    let group = UUID()
    let previousGroups = Set(boxes[index].items.filter { selectedItems.contains($0.id) }.compactMap(\.stackID))
    let members = boxes[index].items.indices.filter { position in
      let item = boxes[index].items[position]
      return selectedItems.contains(item.id) || item.stackID.map(previousGroups.contains) == true
    }
    guard let first = members.first, members.count > 1 else { return }
    for position in members {
      boxes[index].items[position].stackID = group
      boxes[index].items[position].stackName = nil
    }
    selectedItems = [boxes[index].items[first].id]
    changed()
    notice = "Stacked \(members.count) items."
  }

  func renameStack(_ stackID: UUID, in boxID: UUID, to name: String) {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !busy, let index = boxes.firstIndex(where: { $0.id == boxID }), name.count <= 80 else { return }
    for i in boxes[index].items.indices where boxes[index].items[i].stackID == stackID {
      boxes[index].items[i].stackName = name.isEmpty ? nil : name
    }
    changed()
  }

  func moveStackMember(_ id: UUID, in boxID: UUID, by step: Int) {
    guard !busy, let index = boxes.firstIndex(where: { $0.id == boxID }),
      let source = boxes[index].items.firstIndex(where: { $0.id == id }),
      let stackID = boxes[index].items[source].stackID else { return }
    let indices = boxes[index].items.indices.filter { boxes[index].items[$0].stackID == stackID }
    guard let position = indices.firstIndex(of: source), indices.indices.contains(position + step) else { return }
    boxes[index].items.swapAt(source, indices[position + step])
    changed()
  }

  func unstack(_ itemID: UUID) {
    guard !busy, let i = index, let stackID = boxes[i].items.first(where: { $0.id == itemID })?.stackID else { return }
    for j in boxes[i].items.indices where boxes[i].items[j].stackID == stackID {
      boxes[i].items[j].stackID = nil
      boxes[i].items[j].stackName = nil
    }
    selectedItems = []
    changed()
  }
  func selectAll() { selectedItems = Set(items.map(\.id)) }
  func remove(_ ids: Set<UUID>) {
    guard !busy, let i = index else { return }
    error = nil
    notice = nil
    boxes[i].items.removeAll { ids.contains($0.id) }
    selectedItems.subtract(ids)
    changed()
    reconcileAccess()
  }
  /// Pin/unpin an item. Pinned items survive the self-cleaning auto-clear.
  func togglePin(_ id: UUID) {
    guard !busy, let i = index, let j = boxes[i].items.firstIndex(where: { $0.id == id }) else {
      return
    }
    boxes[i].items[j].isPinned.toggle()
    changed()
  }
  /// Pin or unpin every selected item at once.
  func togglePinSelected() {
    guard !busy, let i = index, !selectedItems.isEmpty else { return }
    let targets = boxes[i].items.filter { selectedItems.contains($0.id) }
    let pinning = targets.contains { !$0.isPinned }
    for j in boxes[i].items.indices where selectedItems.contains(boxes[i].items[j].id) {
      boxes[i].items[j].isPinned = pinning
    }
    changed()
    notice = pinning ? "Pinned — these will survive the shelf's self-cleaning."
      : "Unpinned."
  }
  /// Self-cleaning shelf: drop unpinned items older than 24h. Pinned items always survive.
  /// Inspired by FlowShelf's self-cleaning model — shelves rot into junk drawers otherwise.
  func clearStaleItems() {
    guard !busy else { return }
    let cutoff = Date().addingTimeInterval(-24 * 3600)
    var removed = 0
    for b in boxes.indices {
      let before = boxes[b].items.count
      boxes[b].items.removeAll { !$0.isPinned && $0.addedAt < cutoff }
      removed += before - boxes[b].items.count
    }
    if removed > 0 {
      selectedItems.removeAll()
      changed()
      reconcileAccess()
      notice = "Cleared \(removed) stale item\(removed == 1 ? "" : "s"). Pinned items were kept."
    }
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
      error = "Preparing images needs an active licence."
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
    job = Task { [self] in
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
      lastManifest = ""  // Prepared names/sizes changed; rebuild the manifest on next copy.
      progress = 0
      save()
      if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }
  }
  func prepareVideos() {
    refreshLicense()
    guard canExport, !busy, receivingCount == 0, let boxID = selectedBox, !videoItems.isEmpty else { return }
    let targets = videoItems
    let settings = videoRecipe
    let cancellation = CancellationToken()
    token = cancellation; phase = .preparing; progress = 0; showVideoPrepare = false
    job = Task {
      var results: [(UUID, PreparedVideo)] = []
      var failures: [String] = []
      for (offset, item) in targets.enumerated() {
        if cancellation.isCancelled { break }
        progress = Double(offset) / Double(targets.count); progressLabel = "Preparing \(item.displayName)"
        do {
          let result = try await VideoPipeline.prepare(source: item.sourceURL, recipe: settings, token: cancellation)
          results.append((item.id, result))
        } catch { if !cancellation.isCancelled { failures.append(error.localizedDescription) } }
      }
      if !cancellation.isCancelled, let position = boxes.firstIndex(where: { $0.id == boxID }) {
        var box = boxes[position]
        for (itemID, result) in results {
          if let itemIndex = box.items.firstIndex(where: { $0.id == itemID }) {
            box.items[itemIndex].preparedPath = result.url.path
            box.items[itemIndex].preparedBytes = result.bytes
            box.items[itemIndex].preparedDescription = result.description
          } else { StoragePaths.deleteOwned(result.url) }
        }
        box.lastArchivePath = nil; box.updatedAt = Date(); boxes[position] = box
        notice = "\(results.count) video \(results.count == 1 ? "copy" : "copies") prepared. Originals are safe."
      } else {
        results.forEach { StoragePaths.deleteOwned($0.1.url) }
        notice = "Video preparation cancelled. Originals are unchanged."
      }
      phase = .open; token = nil; job = nil; progress = 0; archiveURL = nil; lastManifest = ""
      save()
      if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }
  }
  func transformDocuments(_ kind: DocumentTransformKind, itemIDs: Set<UUID>? = nil) {
    refreshLicense()
    guard canExport else {
      error = "Transforming files needs an active licence."
      return
    }
    guard !busy, receivingCount == 0, let boxID = selectedBox else { return }
    let candidates = itemIDs.map { ids in items.filter { ids.contains($0.id) } } ?? transformItems
    let targets = candidates.filter {
      !$0.isDirectory && DocumentTransformPipeline.available(for: [$0.effectiveURL]).contains(kind)
    }
    guard !targets.isEmpty else {
      notice = "Select a compatible image, PDF, document or spreadsheet first."
      return
    }
    let cancellation = CancellationToken()
    token = cancellation
    phase = .preparing
    progress = 0
    showTransform = false
    job = Task {
      var results: [DocumentTransformResult] = []
      var failures: [String] = []
      for (offset, item) in targets.enumerated() {
        if cancellation.isCancelled { break }
        progress = Double(offset) / Double(targets.count)
        progressLabel = "Transforming \(item.displayName)"
        do {
          let result = try await DocumentTransformPipeline.transform(
            source: item.effectiveURL, kind: kind, token: cancellation)
          results.append(result)
        } catch {
          if !cancellation.isCancelled { failures.append(error.localizedDescription) }
        }
      }
      if !cancellation.isCancelled, let position = boxes.firstIndex(where: { $0.id == boxID }) {
        var box = boxes[position]
        var known = Set(box.items.map(\.sourcePath))
        for result in results {
          do {
            let info = try FileTree.inspect(result.url)
            guard !known.contains(result.url.path), box.items.count < 2000 else {
              _ = StoragePaths.deleteOwned(result.ownedRoot)
              continue
            }
            box.items.append(ParcelItem(
              sourcePath: result.url.path, displayName: result.url.lastPathComponent,
              isDirectory: info.folder, byteCount: info.folder ? 0 : info.bytes))
            known.insert(result.url.path)
          } catch {
            _ = StoragePaths.deleteOwned(result.ownedRoot)
            failures.append(error.localizedDescription)
          }
        }
        box.lastArchivePath = nil
        box.updatedAt = Date()
        boxes[position] = box
        bounce += results.isEmpty ? 0 : 1
        notice = "Added \(results.count) transformed \(results.count == 1 ? "copy" : "copies"). Originals are safe."
      } else {
        results.forEach { _ = StoragePaths.deleteOwned($0.ownedRoot) }
        notice = "Transform cancelled. Originals are unchanged."
      }
      phase = .open
      token = nil
      job = nil
      progress = 0
      archiveURL = nil
      lastManifest = ""
      save()
      if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }
  }
  func quickConvert(
    _ urls: [URL], action: QuickConvertAction, outputs: (([URL]) -> Void)? = nil,
    completion: @escaping @MainActor (Int, String?) -> Void
  ) {
    refreshLicense()
    guard canExport, !busy, receivingCount == 0, libraryWritable, !urls.isEmpty,
      QuickConvertAction.available(for: urls).contains(action),
      let boxID = ShelfRanking.primary(boxes)?.id ?? selectedBox
    else { completion(0, "This selection cannot be converted right now."); return }
    let cancellation = CancellationToken()
    token = cancellation; phase = .preparing; progress = 0
    job = Task {
      var results: [QuickConversionResult] = []
      var failures: [String] = []
      for (offset, url) in urls.enumerated() {
        if cancellation.isCancelled { break }
        progress = Double(offset) / Double(urls.count)
        progressLabel = "Converting \(url.lastPathComponent)"
        do {
          results.append(try await QuickConversionPipeline.convert(source: url, action: action, token: cancellation))
        } catch { if !cancellation.isCancelled { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") } }
      }
      let committed = finishShelfPreparation(results, in: boxID, cancellation: cancellation, failures: &failures)
      outputs?(committed)
      completion(committed.count, failures.isEmpty ? nil : failures.joined(separator: "\n"))
    }
  }

  func prepareShelfArchive(_ urls: [URL], operation: ShelfFileOperation, format: PackFormat,
    strength: PackStrength, completion: @escaping @MainActor ([URL], String?) -> Void) {
    refreshLicense()
    guard !busy, receivingCount == 0, libraryWritable, canExport, !urls.isEmpty,
      let boxID = ShelfRanking.primary(boxes)?.id ?? selectedBox else {
      completion([], "The File Shelf cannot accept results right now."); return
    }
    let cancellation = CancellationToken()
    token = cancellation; phase = .preparing; progress = 0; progressLabel = operation.rawValue + "ing…"
    job = Task {
      var results: [QuickConversionResult] = []
      var failures: [String] = []
      do {
        if operation == .compress {
          let output = try await Task.detached(priority: .userInitiated) { [weak self] in
            try ShelfArchivePipeline.compress(urls, format: format, strength: strength, token: cancellation) { progress, label in
              Task { @MainActor [weak self] in
                guard let self, self.token === cancellation else { return }
                self.progress = progress; self.progressLabel = label
              }
            }
          }.value
          results.append(output)
        } else if operation == .extract {
          for (index, url) in urls.enumerated() {
            try cancellation.check()
            progress = Double(index) / Double(urls.count)
            progressLabel = "Extracting \(url.lastPathComponent)"
            guard url.pathExtension.lowercased() == "zip" else { throw ParcelError.unsupportedSource(url.lastPathComponent) }
            results.append(try await Task.detached(priority: .userInitiated) {
              try ShelfArchivePipeline.extractZIP(url, token: cancellation)
            }.value)
          }
        }
      } catch { if !cancellation.isCancelled { failures.append(error.localizedDescription) } }
      let committed = finishShelfPreparation(results, in: boxID, cancellation: cancellation, failures: &failures)
      completion(committed, failures.isEmpty ? nil : failures.joined(separator: "\n"))
    }
  }

  private func finishShelfPreparation(_ results: [QuickConversionResult], in boxID: UUID,
    cancellation: CancellationToken, failures: inout [String]) -> [URL] {
    defer { phase = .open; token = nil; job = nil; progress = 0; archiveURL = nil; lastManifest = "" }
    guard !cancellation.isCancelled, let index = boxes.firstIndex(where: { $0.id == boxID }) else {
      results.forEach { _ = StoragePaths.deleteOwned($0.ownedRoot) }
      return []
    }
    let previous = boxes[index]
    let previousSelection = selectedBox
    var box = previous
    var accepted: [QuickConversionResult] = []
    for result in results {
      do {
        let info = try FileTree.inspect(result.url)
        guard box.items.count < 2000, info.folder || info.bytes > 0 else {
          throw ParcelError.storageError("The result is empty or the File Shelf is full.")
        }
        box.items.append(ParcelItem(sourcePath: result.url.path, displayName: result.url.lastPathComponent,
          isDirectory: info.folder, byteCount: info.folder ? 0 : info.bytes))
        accepted.append(result)
      } catch {
        _ = StoragePaths.deleteOwned(result.ownedRoot)
        failures.append(error.localizedDescription)
      }
    }
    guard !accepted.isEmpty else { return [] }
    box.updatedAt = Date(); box.lastArchivePath = nil; boxes[index] = box; selectedBox = boxID
    do {
      try persistLibrary()
      bounce += 1
      notice = "\(accepted.count) ready in the File Shelf."
      return accepted.map(\.url)
    } catch {
      boxes[index] = previous; selectedBox = previousSelection
      accepted.forEach { _ = StoragePaths.deleteOwned($0.ownedRoot) }
      failures.append("Could not save the File Shelf: \(error.localizedDescription)")
      return []
    }
  }
  func seal(reportError: ((String) -> Void)? = nil, options override: PackagingOptions? = nil,
            finished: ((URL?) -> Void)? = nil) {
    let fail: (String) -> Void = { message in
      if let reportError { reportError(message) } else { self.error = message }
    }
    refreshLicense()
    guard !busy, receivingCount == 0, canExport, let box = current, !box.items.isEmpty else {
      finished?(nil)
      return
    }
    guard box.items.allSatisfy({ FileManager.default.fileExists(atPath: $0.effectiveURL.path) })
    else {
      fail("A parcel item is missing. Locate it, restore its original, or remove it before sealing.")
      finished?(nil)
      return
    }
    let options = override ?? packaging
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
        fail(error.localizedDescription)
        finished?(nil)
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
    job = Task { [self] in
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
        if let icon = NSApplication.shared.applicationIconImage {
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
          fail(error.localizedDescription)
        }
      }
      token = nil
      job = nil
      finished?(phase == .ready ? archiveURL : nil)
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
  /// Copies a text file's contents straight to the clipboard — Dropover's
  /// "copy text-file contents" as a built-in Parcel action.
  func copyTextContents(of item: ParcelItem) {
    guard !busy else { return }
    let url = item.effectiveURL
    guard TextRecognition.isProbablyText(url: url) else {
      notice = "\"\(item.displayName)\" doesn't look like a text file."
      return
    }
    do {
      let text = try String(contentsOf: url, encoding: .utf8)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
      Toaster.shared.copied("Text contents")
      notice = "Copied the contents of \"\(item.displayName)\"."
    } catch {
      self.error = "Couldn't read \"\(item.displayName)\": \(error.localizedDescription)"
    }
  }
  /// Runs on-device OCR over the parcel's images and copies all recognized
  /// text to the clipboard — Dropover's built-in "extract text" action.
  func extractTextFromImages(itemIDs: Set<UUID>? = nil) {
    guard !extractingText else { return }
    let candidates = itemIDs.map { ids in items.filter { ids.contains($0.id) } } ?? workingItems
    let targets = candidates.filter { !$0.isDirectory && ImagePipeline.canPrepare($0.effectiveURL) }
    guard !targets.isEmpty else {
      notice = "Add an image to the parcel first, then extract its text."
      return
    }
    extractingText = true
    notice = "Reading text from \(targets.count) image\(targets.count == 1 ? "" : "s")…"
    Task { [weak self] in
      var parts: [String] = []
      for item in targets {
        if Task.isCancelled { break }
        guard FileManager.default.fileExists(atPath: item.effectiveURL.path) else { continue }
        if let text = await TextRecognition.recognizeText(in: item.effectiveURL) {
          parts.append(text)
        }
      }
      let combined = parts.joined(separator: "\n\n")
      await MainActor.run { [weak self] in
        guard let self else { return }
        self.extractingText = false
        if parts.isEmpty {
          self.notice = "No readable text found in those images."
        } else {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(combined, forType: .string)
          Toaster.shared.copied("Extracted text")
          self.notice = "Copied text from \(parts.count) image\(parts.count == 1 ? "" : "s")."
        }
      }
    }
  }
  func copyInlineText(_ item: ParcelItem) {
    guard let text = item.inlineText else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    Toaster.shared.copied("Text")
    notice = "Copied text from \"\(item.displayName)\"."
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
  @discardableResult func copyArchiveToClipboard(to board: NSPasteboard = .general) -> Bool {
    guard canExport, !busy, ready, let zip = archiveURL else { return false }
    board.clearContents()
    guard board.writeObjects([zip as NSURL]) else { return false }
    Toaster.shared.copied("Parcel \(zip.pathExtension.uppercased())")
    notice = "Parcel \(zip.pathExtension.uppercased()) copied — paste it anywhere."
    return true
  }
  /// A LOCAL file link to the packed parcel — it only works on this
  /// Mac, it is not a cloud/internet share link. Paste it into any app
  /// on this Mac to hand the parcel over.
  func copyArchiveLink() {
    guard canExport, !busy, ready, let url = archiveURL else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(url.absoluteString, forType: .string)
    Toaster.shared.copied("Local file link")
    notice = "Local file link copied — it opens this parcel on your Mac only, not over the internet."
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
        .init(boxes: boxes, selectedBox: selectedBox, trashedBoxes: trashedBoxes), to: StoragePaths.library)
      libraryWritable = true
      error = nil
      notice = "The previous library was backed up before starting fresh."
    } catch { self.error = "Could not back up the library: \(error.localizedDescription)" }
  }
  var needsLibraryRecovery: Bool { !libraryWritable }
}

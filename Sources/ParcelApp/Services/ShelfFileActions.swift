import AppKit
import ParcelCore
import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

enum ShelfFileOperation: String, CaseIterable, Identifiable {
  case convert = "Convert", compress = "Compress", extract = "Extract"
  var id: Self { self }
}

enum ShelfArchivePipeline {
  static func compress(_ urls: [URL], format: PackFormat, strength: PackStrength, token: CancellationToken,
                       progress: @escaping @Sendable (Double, String) -> Void) throws -> QuickConversionResult {
    let name = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "Skippy files"
    return try prepare(name: name, extension: format.fileExtension) { destination in
      var options = PackagingOptions()
      options.includeManifest = false
      options.format = format
      options.strength = strength
      let inputs = urls.map { PackageInput(url: $0, desiredName: $0.lastPathComponent) }
      _ = try PackageBuilder.build(inputs: inputs, title: name, destination: destination,
        options: options, token: token, progress: progress)
    }
  }

  static func extractZIP(_ url: URL, token: CancellationToken) throws -> QuickConversionResult {
    try prepare(name: url.deletingPathExtension().lastPathComponent, extension: "") { destination in
      let archive = try Archive(url: url, accessMode: .read)
      let fm = FileManager.default
      try fm.createDirectory(at: destination, withIntermediateDirectories: true)
      var total: UInt64 = 0
      var paths = Set<String>()
      for entry in archive {
        try token.check()
        let components = entry.path.split(separator: "/", omittingEmptySubsequences: false)
        guard !entry.path.hasPrefix("/"), !entry.path.contains("\\"),
          !components.contains(".."), !components.contains("."),
          entry.type == .file || entry.type == .directory else {
          throw ParcelError.storageError("The ZIP contains a link or an unsafe path.")
        }
        let target = destination.appendingPathComponent(entry.path).standardizedFileURL
        guard target.path.hasPrefix(destination.path + "/"),
          paths.insert(target.path.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
          throw ParcelError.storageError("The ZIP contains duplicate or unsafe paths.")
        }
        let size = UInt64(entry.uncompressedSize)
        guard paths.count <= 20_000, size <= 4_000_000_000 - total else {
          throw ParcelError.storageError("The ZIP exceeds Skippy’s extraction limit.")
        }
        total += size
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let progress = Progress(totalUnitCount: 0)
        token.track(progress)
        if entry.type == .directory {
          try fm.createDirectory(at: target, withIntermediateDirectories: true)
        } else {
          let checksum = try archive.extract(entry, to: target, progress: progress)
          guard checksum == entry.checksum else { throw ParcelError.storageError("The ZIP failed its integrity check.") }
        }
      }
      try token.check()
      guard !paths.isEmpty else { throw ParcelError.storageError("The ZIP is empty.") }
    }
  }

  private static func prepare(name: String, extension fileExtension: String,
                              work: (URL) throws -> Void) throws -> QuickConversionResult {
    let root = StoragePaths.prepared.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let name = NamePolicy.safeArchiveStem(name)
    let destination = root.appendingPathComponent(fileExtension.isEmpty ? name : name + "." + fileExtension)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    do {
      try work(destination)
      return .init(url: destination, ownedRoot: root)
    } catch {
      _ = StoragePaths.deleteOwned(root)
      throw error
    }
  }
}

@MainActor final class ShelfFileActions {
  static let shared = ShelfFileActions()
  private var window: NSWindow?
  private var shelfWindow: NSPanel?

  private func resultShelf() -> NSPanel {
    if let shelfWindow { return shelfWindow }
    let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 330, height: 330),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    panel.title = "Parcels File Shelf"
    panel.level = .floating
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.appearance = NSAppearance(named: .aqua)
    shelfWindow = panel
    return panel
  }

  func showResults(_ urls: [URL], beside anchor: NSWindow? = nil) {
    let panel = resultShelf()
    panel.contentView = NSHostingView(rootView: ParcelsShelfContents(shelf: .shared,
      store: ParcelRuntime.store, skin: .slate, highlighted: urls).background(Ink.paper))
    if !panel.isVisible {
      let visible = anchor?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
      if let anchor, let visible {
        let frame = QuiverSurface.companionPanel(at: anchor.frame, within: visible, size: panel.frame.size)
        panel.setFrame(frame, display: true)
      } else {
        panel.center()
      }
    }
    panel.orderFrontRegardless()
  }

  func open(_ operation: ShelfFileOperation, urls: [URL] = []) {
    if let existing = window, existing.isVisible, ParcelRuntime.store.busy {
      existing.makeKeyAndOrderFront(nil)
      return
    }
    window?.orderOut(nil)
    let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 372, height: 298),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    panel.title = operation.rawValue + " in Parcels"
    panel.isReleasedWhenClosed = false
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.contentView = NSHostingView(rootView: ShelfFileActionView(store: ParcelRuntime.store,
      operation: operation, urls: urls, presentResults: { [weak self, weak panel] urls in
        self?.showResults(urls, beside: panel)
      }))
    panel.appearance = NSAppearance(named: .aqua)
    panel.center()
    if !urls.isEmpty, let bounds = panel.screen?.visibleFrame {
      panel.setFrameOrigin(NSPoint(x: max(bounds.minX + 12, bounds.midX - 353), y: panel.frame.minY))
    }
    window = panel
    panel.makeKeyAndOrderFront(nil)
    if !urls.isEmpty { showResults([], beside: panel) }
    NSApp.activate(ignoringOtherApps: true)
  }
}

struct ShelfFileActionView: View {
  @ObservedObject var store: ParcelStore
  let operation: ShelfFileOperation
  @State private var urls: [URL]
  @State private var conversion: QuickConvertAction?
  @State private var format = PackFormat.zip
  @State private var strength = PackStrength.balanced
  @State private var result: [URL] = []
  @State private var message: String?
  @State private var running = false
  @State private var sourceIdentity: SourceIdentity?
  @State private var confirmDiscard = false
  @State private var confirmReplace = false
  private let presentResults: (([URL]) -> Void)?

  init(store: ParcelStore, operation: ShelfFileOperation, urls: [URL] = [],
       presentResults: (([URL]) -> Void)? = nil) {
    self.store = store
    self.operation = operation
    self.presentResults = presentResults
    _urls = State(initialValue: urls)
    _conversion = State(initialValue: QuickConvertAction.available(for: urls).first)
  }

  private struct SourceIdentity: Equatable {
    let size: Int
    let modified: Date
    let identifier: NSObject
    init?(_ url: URL) {
      guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        .contentModificationDateKey, .fileResourceIdentifierKey]),
        values.isRegularFile == true, values.isSymbolicLink != true,
        let size = values.fileSize, let modified = values.contentModificationDate,
        let identifier = values.fileResourceIdentifier as? NSObject else { return nil }
      self.size = size; self.modified = modified; self.identifier = identifier
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 11) {
        HStack {
          Text(operation.rawValue).font(.title2.bold())
          Spacer()
          Button("Paste files") {
            let files = ParcelFileService.fileURLs(from: .general)
            if files.isEmpty { message = "Copy files in Finder before pasting." } else { updateFiles(files) }
          }.disabled(running)
          Button("Choose files…", action: choose).disabled(running)
        }
        Text(urls.isEmpty ? "Choose or drop files" : urls.map(\.lastPathComponent).joined(separator: ", "))
          .lineLimit(2).font(.callout)
          .frame(maxWidth: .infinity, alignment: .leading).padding(9)
          .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
          .dropDestination(for: URL.self) { files, _ in
            guard !running else { return false }
            updateFiles(files.filter(\.isFileURL)); return !urls.isEmpty
          }
        if operation == .convert {
          Picker("Convert to", selection: $conversion) {
            if conversion == nil { Text("Choose a compatible file").tag(nil as QuickConvertAction?) }
            ForEach(QuickConvertAction.available(for: urls)) { action in Text(action.label).tag(Optional(action)) }
          }.disabled(running || conversion == nil)
          if conversion == .numbersExcel {
            Text("Requires Apple Numbers and macOS Automation access.").font(.caption).foregroundStyle(.secondary)
          }
        } else if operation == .compress {
          Picker("Archive format", selection: $format) {
            ForEach(PackFormat.allCases, id: \.self) {
              Text($0.label + ($0.isUsable ? "" : " (tool required)")).tag($0)
            }
          }.disabled(running)
          Picker("Compression", selection: $strength) {
            ForEach(PackStrength.allCases, id: \.self) { Text($0.label).tag($0) }
          }.disabled(running)
        } else {
          Text("Select ZIP archives to expand into the File Shelf.").font(.caption)
        }
        LabeledContent { Label("File Shelf", systemImage: "tray") }
          label: { Text("Save to") }
        if operation == .convert && result.isEmpty {
          LabeledContent("Original", value: "Keep original").foregroundStyle(.secondary)
        }
        if running { ProgressView(store.progressLabel, value: store.progress) }
        if let message { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        if !result.isEmpty {
          HStack {
            Button("Copy result") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.writeObjects(result.map { $0 as NSURL })
            }
            Button("Show in File Shelf") {
              if let presentResults { presentResults(result) }
              else { ShelfFileActions.shared.showResults(result, beside: NSApp.keyWindow) }
            }
            Menu("Export") {
              Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(result) }
              Button("Save Copy…", action: saveCopies)
            }
            if sourceIdentity != nil && operation == .convert {
              Menu("Original") {
                if urls.first?.pathExtension.lowercased() == result.first?.pathExtension.lowercased() && result.count == 1 {
                  Button("Replace Original…", role: .destructive) { confirmReplace = true }
                }
                Button("Move Original to Trash…", role: .destructive) { confirmDiscard = true }
              }.fixedSize()
            }
          }
        }
        HStack {
          Spacer()
          if running { Button("Cancel") { store.cancel() } }
          else {
            Button(operation.rawValue, action: start).keyboardShortcut(.defaultAction)
              .disabled(urls.isEmpty || store.busy || (operation == .convert && conversion == nil) ||
                (operation == .compress && !format.isUsable) ||
                (operation == .extract && !urls.allSatisfy { $0.pathExtension.lowercased() == "zip" }))
          }
        }
      }.padding(15)
    }
    .preferredColorScheme(.light)
    .background(Ink.paper)
    .tint(Ink.green)
    .confirmationDialog("Move the original to Trash?", isPresented: $confirmDiscard) {
      Button("Move to Trash", role: .destructive) { changeOriginal(replace: false) }
    } message: { Text("The completed conversion stays in the File Shelf.") }
    .confirmationDialog("Replace the original?", isPresented: $confirmReplace) {
      Button("Replace Original", role: .destructive) { changeOriginal(replace: true) }
    } message: { Text("Skippy keeps a backup next to the original.") }
  }

  private func saveCopies() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.prompt = "Save Here"
    guard panel.runModal() == .OK, let folder = panel.url else { return }
    let files = result
    Task {
      do {
        try await Task.detached(priority: .userInitiated) {
          let fm = FileManager.default
          var names = Set(try fm.contentsOfDirectory(atPath: folder.path).map(NamePolicy.key))
          for source in files {
            let name = try NamePolicy.unique(source.lastPathComponent, used: &names)
            try fm.copyItem(at: source, to: folder.appendingPathComponent(name))
          }
        }.value
        message = "Saved \(files.count) " + (files.count == 1 ? "copy." : "copies.")
      } catch { message = error.localizedDescription }
    }
  }

  private func choose() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = operation == .compress
    panel.allowsMultipleSelection = true
    if operation == .extract { panel.allowedContentTypes = [.zip] }
    if panel.runModal() == .OK { updateFiles(panel.urls) }
  }

  private func updateFiles(_ files: [URL]) {
    urls = files
    conversion = QuickConvertAction.available(for: files).first
    result = []; message = nil; sourceIdentity = nil
  }

  private func start() {
    running = true; result = []; message = nil
    sourceIdentity = urls.count == 1 ? SourceIdentity(urls[0]) : nil
    let completion: ([URL], String?) -> Void = { output, error in
      result = output
      running = false
      message = error ?? (output.isEmpty ? "Cancelled." : "Ready in the File Shelf. Originals kept.")
      if error != nil { sourceIdentity = nil }
      if !output.isEmpty { presentResults?(output) }
    }
    if operation == .convert, let conversion {
      store.quickConvert(urls, action: conversion, outputs: { output in result = output }) { _, error in
        completion(result, error)
      }
    } else {
      store.prepareShelfArchive(urls, operation: operation, format: format, strength: strength, completion: completion)
    }
  }

  private func changeOriginal(replace: Bool) {
    guard urls.count == 1, result.count == 1, let source = urls.first, let output = result.first,
      let sourceIdentity, sourceIdentity == SourceIdentity(source),
      let outputInfo = SourceIdentity(output), outputInfo.size > 0 else {
      message = "The source or result changed. The original was kept."
      return
    }
    let fm = FileManager.default
    do {
      if replace {
        guard source.pathExtension.lowercased() == output.pathExtension.lowercased() else { return }
        let staged = source.deletingLastPathComponent().appendingPathComponent(".skippy-\(UUID().uuidString)")
        let backup = ".skippy-backup-" + String(UUID().uuidString.prefix(8)) + "-" + source.lastPathComponent
        defer { try? fm.removeItem(at: staged) }
        try fm.copyItem(at: output, to: staged)
        guard sourceIdentity == SourceIdentity(source) else { throw ParcelError.sourceChanged(source.lastPathComponent) }
        _ = try fm.replaceItemAt(source, withItemAt: staged, backupItemName: String(backup),
          options: [.withoutDeletingBackupItem])
        message = "Original replaced. Backup: \(backup)"
      } else {
        guard sourceIdentity == SourceIdentity(source) else { throw ParcelError.sourceChanged(source.lastPathComponent) }
        try fm.trashItem(at: source, resultingItemURL: nil)
        message = "Original moved to Trash."
      }
      self.sourceIdentity = nil
    } catch { message = error.localizedDescription }
  }
}

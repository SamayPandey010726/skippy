import AppKit
import ParcelCore
import SwiftUI
import UniformTypeIdentifiers

struct ItemListView: View {
  @EnvironmentObject private var store: ParcelStore
  @State private var renaming: ParcelItem?
  @State private var comparing: ParcelItem?
  @StateObject private var skins = SkinStore.shared
  @FocusState private var listFocused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("INSIDE YOUR PARCEL").font(.system(size: 9, weight: .semibold)).tracking(1.7)
        Spacer()
        if !store.selectedItems.isEmpty {
          Button("Clear selection") { store.selectedItems = [] }.buttonStyle(.plain).font(
            .system(size: 10))
          Text("\(store.selectedItems.count) selected").font(.system(size: 10))
        }
      }
      .foregroundStyle(Ink.secondary)
      if store.isSearching {
        Text(
          "\(store.filteredItems.count) match\(store.filteredItems.count == 1 ? "" : "es") for “\(store.searchText)” in this parcel."
        ).font(.system(size: 11)).foregroundStyle(Ink.moss)
      }
      if store.filteredItems.isEmpty {
        if store.isSearching {
          HStack(spacing: 14) {
            Image(systemName: "magnifyingglass").font(.system(size: 22, weight: .ultraLight))
              .foregroundStyle(Ink.moss)
            VStack(alignment: .leading, spacing: 5) {
              Text("Nothing matches here.").font(.system(size: 12, weight: .medium))
              Text("Try another parcel from the sidebar.").font(.system(size: 11))
                .foregroundStyle(Ink.secondary)
            }
            Spacer()
          }.padding(20).background(Ink.canvas, in: RoundedRectangle(cornerRadius: 13))
        } else {
          HStack(spacing: 14) {
            Image(systemName: "plus.rectangle.on.folder").font(.system(size: 25, weight: .ultraLight))
              .foregroundStyle(Ink.moss)
            VStack(alignment: .leading, spacing: 5) {
              Text("Start with a few pieces.").font(.system(size: 12, weight: .medium))
              Text("Files, folders and images are all welcome. Pin what matters — the shelf tidies itself daily.")
                .font(.system(size: 11))
                .foregroundStyle(Ink.secondary)
            }
            Spacer()
            Button("Browse…") { store.addFilesPanel() }.buttonStyle(QuietButtonStyle())
          }.padding(20).background(Ink.canvas, in: RoundedRectangle(cornerRadius: 13)).overlay(
            RoundedRectangle(cornerRadius: 13).stroke(
              Ink.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
      } else {
        LazyVStack(spacing: 6) {
          ForEach(store.filteredItems) { item in
            itemRow(item)
              .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)))
          }
        }.animation(Motion.layoutRelayout, value: store.filteredItems.map(\.id))
        HStack {
          Text("Names and order apply when you drag items out.").font(.system(size: 10))
            .foregroundStyle(Ink.secondary)
          Spacer()
          if !store.selectedItems.isEmpty {
            Button {
              store.remove(store.selectedItems)
            } label: {
              Label("Remove", systemImage: "minus.circle")
            }.buttonStyle(QuietButtonStyle()).disabled(store.busy)
          }
        }
      }
    }
    .focusable().focused($listFocused).focusEffectDisabled()
    .onMoveCommand { direction in
      let step: Int
      switch direction {
      case .up: step = -1
      case .down: step = 1
      default: return
      }
      let items = store.filteredItems
      guard !items.isEmpty else { return }
      let current = items.firstIndex { store.selectedItems.contains($0.id) }
      let next = current.map { min(max($0 + step, 0), items.count - 1) } ?? (step > 0 ? 0 : items.count - 1)
      store.selectedItems = [items[next].id]
    }
    .onKeyPress(.space) {
      let urls = store.filteredItems.filter { store.selectedItems.contains($0.id) }.map(\.effectiveURL)
      guard !urls.isEmpty else { return .ignored }
      QuickLookController.shared.show(urls)
      return .handled
    }
    .onExitCommand { store.selectedItems = []; listFocused = false }
    .sheet(item: $renaming) { item in
      RenameSheet(
        title: "Rename in this parcel", initial: item.displayName,
        caption: "This name is used when you drag the item out or pack it."
      ) { name in store.renameItem(item.id, name: name) }
    }
    .sheet(item: $comparing) { item in ImageComparisonView(item: item) }
  }
  private func itemRow(_ item: ParcelItem) -> some View {
    let available = FileManager.default.fileExists(atPath: item.effectiveURL.path)
    return RowPressContainer {
      HStack(spacing: 12) {
      Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundStyle(Ink.line)
        .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
        .help("Drag this handle to reorder")
      ZStack {
        RoundedRectangle(cornerRadius: 8).fill(Ink.cream)
        FileThumbnail(url: item.effectiveURL, size: 39)
        DragOutSurface(
          urls: available && store.canExport ? [item.effectiveURL] : [], outgoingText: item.inlineText, enabled: !store.busy,
          tap: { store.toggleSelection(item.id); listFocused = true })
      }.frame(width: 49, height: 49)
      VStack(alignment: .leading, spacing: 5) {
        Text(item.effectiveName).font(.system(size: 12, weight: .medium)).lineLimit(1)
          .accessibilityLabel(
            "\(item.effectiveName), \(item.isDirectory ? "folder" : byteString(item.effectiveBytes))\(item.isPinned ? ", pinned" : "")")
        HStack(spacing: 6) {
          Text(
            available
              ? (item.isDirectory ? "Folder" : byteString(item.effectiveBytes)) : "Needs locating"
          ).foregroundStyle(available ? Ink.secondary : .orange)
          if let desc = item.preparedDescription {
            Text("·")
            Text(desc).foregroundStyle(Ink.moss).lineLimit(1)
          }
        }.font(.system(size: 10))
      }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
      .onTapGesture { store.toggleSelection(item.id); listFocused = true }
      if item.isPinned {
        Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Ink.moss).help(
          "Pinned — kept when the shelf self-cleans")
      }
      if item.preparedPath != nil {
        Button {
          comparing = item
        } label: {
          Image(systemName: "rectangle.split.2x1").font(.system(size: 13))
        }.buttonStyle(.plain).foregroundStyle(Ink.moss).help("Compare original and prepared copy")
      }
      Button {
        QuickLookController.shared.show([item.effectiveURL])
      } label: {
        Image(systemName: "eye").font(.system(size: 12))
      }.buttonStyle(.plain).foregroundStyle(Ink.secondary).disabled(!available).help("Quick Look")
        .accessibilityLabel("Quick Look \(item.displayName)")
      Button {
        store.remove([item.id])
      } label: {
        Image(systemName: "xmark").font(.system(size: 9))
      }.buttonStyle(.plain).foregroundStyle(Ink.secondary).disabled(store.busy).help(
        "Remove from parcel; keep original")
        .accessibilityLabel("Remove \(item.displayName) from parcel")
    }.padding(.horizontal, 13).padding(.vertical, 9)
      .background(
        store.selectedItems.contains(item.id) ? Ink.paleGreen.opacity(0.6) : Ink.canvas,
        in: RoundedRectangle(cornerRadius: 12)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12).stroke(
          store.selectedItems.contains(item.id) ? Ink.moss.opacity(0.5) : Ink.line.opacity(0.7),
          lineWidth: 1)
      )
      .overlay(
        // Specular edge: white gradient fading top-to-bottom.
        RoundedRectangle(cornerRadius: 12)
          .stroke(
            LinearGradient(
              colors: [.white.opacity(0.25), .white.opacity(0)],
              startPoint: .top, endPoint: .bottom),
            lineWidth: 0.5)
      )
      .contextMenu {
        Button("Preview") { QuickLookController.shared.show([item.effectiveURL]) }.disabled(
          !available)
        Button("Copy item") {
          guard let boxID = store.selectedBox else { return }
          do { _ = try store.copyShelfFiles(in: boxID, itemID: item.id) }
          catch { store.error = error.localizedDescription }
        }.disabled(store.busy || !store.canExport)
        Button("Copy all parcel items") {
          guard let boxID = store.selectedBox else { return }
          do { _ = try store.copyShelfFiles(in: boxID) }
          catch { store.error = error.localizedDescription }
        }.disabled(store.busy || !store.canExport)
        Button("Pack parcel") { store.seal() }.disabled(store.busy || store.items.isEmpty || !store.canExport)
        Button("Rename in parcel…") { renaming = item }.disabled(store.busy)
        Button("Show original in Finder") {
          NSWorkspace.shared.activateFileViewerSelecting([item.sourceURL])
        }
        Button("Locate original…") { store.locate(item) }.disabled(store.busy)
        if item.preparedPath != nil { Button("Compare copies…") { comparing = item } }
        if TextRecognition.isProbablyText(url: item.effectiveURL) {
          Button("Copy Contents") { store.copyTextContents(of: item) }.disabled(store.busy)
        }
        if ImagePipeline.canPrepare(item.effectiveURL) {
          Button("Process image…") {
            store.selectedItems = [item.id]
            store.showTransform = true
          }.disabled(store.busy)
          Button("Copy Text with OCR") { store.extractTextFromImages(itemIDs: [item.id]) }
            .disabled(store.busy || store.extractingText)
        }
        if VideoPipeline.canPrepare(item.effectiveURL) {
          Button("Process video…") {
            store.selectedItems = [item.id]
            store.showVideoPrepare = true
          }.disabled(store.busy)
        }
        let transforms = DocumentTransformPipeline.available(for: [item.effectiveURL])
        if !transforms.isEmpty {
          Menu("Transform") {
            ForEach(transforms) { transform in
              Button(transform.label) { store.transformDocuments(transform, itemIDs: [item.id]) }
            }
          }.disabled(store.busy || !store.canExport)
        }
        Button(item.isPinned ? "Unpin" : "Pin") { store.togglePin(item.id) }.disabled(store.busy)
        Divider()
        Button("Remove from parcel", role: .destructive) { store.remove([item.id]) }.disabled(
          store.busy)
      }
      .onDrop(of: [UTType.text], isTargeted: nil) { providers in
        guard !store.busy, let p = providers.first else { return false }
        _ = p.loadObject(ofClass: NSString.self) { object, _ in
          guard let text = object as? String, let id = UUID(uuidString: text) else { return }
          Task { @MainActor in store.reorder(id, before: item.id) }
        }
        return true
      }
    }
  }
}

/// Wraps a row to give it press feedback: squishes slightly while the
/// pointer is down, so the row feels like a physical object being
/// picked up. Uses a zero-distance drag so it doesn't interfere with
/// the row's own buttons or drag-out surface.
private struct RowPressContainer<Content: View>: View {
  @GestureState private var pressing = false
  let content: Content
  init(@ViewBuilder content: () -> Content) { self.content = content() }
  var body: some View {
    content
      .scaleEffect(pressing ? 0.985 : 1)
      .animation(Motion.pressSquish, value: pressing)
      // Simultaneous so it never blocks the row's own drag-out or reorder.
      .simultaneousGesture(
        DragGesture(minimumDistance: 0)
          .updating($pressing) { _, state, _ in state = true }
      )
  }
}

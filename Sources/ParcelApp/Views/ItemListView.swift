import AppKit
import ParcelCore
import SwiftUI
import UniformTypeIdentifiers

struct ItemListView: View {
  @EnvironmentObject private var store: ParcelStore
  @State private var renaming: ParcelItem?
  @State private var comparing: ParcelItem?
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
              Text("Files, folders and images are all welcome.").font(.system(size: 11))
                .foregroundStyle(Ink.secondary)
            }
            Spacer()
            Button("Browse…") { store.addFilesPanel() }.buttonStyle(QuietButtonStyle())
          }.padding(20).background(Ink.canvas, in: RoundedRectangle(cornerRadius: 13)).overlay(
            RoundedRectangle(cornerRadius: 13).stroke(
              Ink.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
      } else {
        LazyVStack(spacing: 6) { ForEach(store.filteredItems) { item in itemRow(item) } }
        HStack {
          Text("Names and order apply to your ZIP copies.").font(.system(size: 10))
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
    }.sheet(item: $renaming) { item in
      RenameSheet(
        title: "Rename in this parcel", initial: item.displayName,
        caption: "The ZIP uses this name. Loose-file drags keep the actual filename."
      ) { name in store.renameItem(item.id, name: name) }
    }
    .sheet(item: $comparing) { item in ImageComparisonView(item: item) }
  }
  private func itemRow(_ item: ParcelItem) -> some View {
    let available = FileManager.default.fileExists(atPath: item.effectiveURL.path)
    return HStack(spacing: 12) {
      Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundStyle(Ink.line)
        .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
        .help("Drag this handle to reorder")
      ZStack {
        RoundedRectangle(cornerRadius: 8).fill(Ink.cream)
        FileThumbnail(url: item.effectiveURL, size: 39)
        DragOutSurface(
          urls: available && store.canExport ? [item.effectiveURL] : [], enabled: !store.busy,
          tap: { store.toggleSelection(item.id) })
      }.frame(width: 49, height: 49)
      VStack(alignment: .leading, spacing: 5) {
        Text(item.effectiveName).font(.system(size: 12, weight: .medium)).lineLimit(1)
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
      }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture {
        store.toggleSelection(item.id)
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
      Button {
        store.remove([item.id])
      } label: {
        Image(systemName: "xmark").font(.system(size: 9))
      }.buttonStyle(.plain).foregroundStyle(Ink.secondary).disabled(store.busy).help(
        "Remove from parcel; keep original")
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
      .contextMenu {
        Button("Preview") { QuickLookController.shared.show([item.effectiveURL]) }.disabled(
          !available)
        Button("Rename in parcel…") { renaming = item }.disabled(store.busy)
        Button("Show original in Finder") {
          NSWorkspace.shared.activateFileViewerSelecting([item.sourceURL])
        }
        Button("Locate original…") { store.locate(item) }.disabled(store.busy)
        if item.preparedPath != nil { Button("Compare copies…") { comparing = item } }
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

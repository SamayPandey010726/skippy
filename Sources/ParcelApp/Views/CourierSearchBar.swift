import ParcelCore
import SwiftUI

struct FileFilterMenu: View {
  @EnvironmentObject private var store: ParcelStore
  @State private var showing = false
  var body: some View {
    Button { showing.toggle() } label: {
      Image(systemName: store.fileTypeFilter != .any || store.fileSizeFilter != .any || store.fileAddedFilter != .anytime
        ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
    }.buttonStyle(.plain).frame(width: 28, height: 28)
      .help("Filter by file type, size and added date").accessibilityLabel("File search filters")
      .popover(isPresented: $showing, arrowEdge: .bottom) {
        VStack(alignment: .leading, spacing: 10) {
      Picker("File type", selection: $store.fileTypeFilter) {
        ForEach(FileSearchType.allCases, id: \.self) { Text($0 == .any ? "Any file type" : $0.label).tag($0) }
      }
      Picker("File size", selection: $store.fileSizeFilter) {
        ForEach(FileSearchSize.allCases, id: \.self) { Text($0.label).tag($0) }
      }
      Picker("Added to Parcel", selection: $store.fileAddedFilter) {
        ForEach(FileSearchAdded.allCases, id: \.self) { Text($0.label).tag($0) }
      }
      Divider()
      Button("Clear search and filters", action: store.clearFileSearch).disabled(!store.isSearching)
        }.padding(14).frame(width: 250)
      }
      .onReceive(NotificationCenter.default.publisher(for: .parcelShowCourierFilters)) { _ in showing = true }
  }
}

struct CourierSearchBar: View {
  @EnvironmentObject private var store: ParcelStore
  @FocusState private var focused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 5) {
        Image(systemName: "magnifyingglass").font(.system(size: 11)).accessibilityHidden(true)
        TextField("Search files · e.g. excel or numbers", text: $store.searchText)
          .textFieldStyle(.plain).font(.system(size: 11)).focused($focused).accessibilityLabel("Search files in this parcel")
          .help("Try ‘File uploaded on 17th’, ‘excel or numbers’, ‘pdf over 10 MB’, or a filename. Dates mean added to Parcel; an ordinal day uses this month.")
          .onExitCommand(perform: store.clearFileSearch)
        if store.isSearching {
          Button(action: store.clearFileSearch) { Image(systemName: "xmark.circle.fill") }
            .buttonStyle(.plain).frame(width: 24, height: 28).accessibilityLabel("Clear file search")
        }
        FileFilterMenu()
      }.padding(.horizontal, 7).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
      if let message = store.fileQuery.warning ?? store.fileQuery.dateDescription {
        Text(message).font(.system(size: 9)).lineLimit(1).foregroundStyle(.secondary)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .parcelFocusCourierSearch)) { _ in focused = true }
  }
}

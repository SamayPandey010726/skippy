import ParcelCore
import SwiftUI

struct BinView: View {
  @EnvironmentObject private var store: ParcelStore
  @Environment(\.dismiss) private var dismiss
  @State private var confirmRemoval = false
  @State private var removing: UUID?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Label("Parcel Bin", systemImage: "trash").font(.system(size: 23, weight: .medium, design: .serif))
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      Text("Restore parcels for 30 days. After that, their library entries are removed automatically. Original files are never deleted.")
        .font(.system(size: 12)).foregroundStyle(Ink.secondary).lineSpacing(4)
      if store.trashedBoxes.isEmpty {
        VStack(spacing: 12) {
          Image(systemName: "trash").font(.system(size: 35, weight: .ultraLight))
          Text("A nice, empty Bin.").font(.system(size: 18, design: .serif))
          Text("Parcels you remove will wait here, just in case.").font(.system(size: 11))
        }.foregroundStyle(Ink.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 8) {
            ForEach(store.trashedBoxes) { entry in
              HStack(spacing: 12) {
                CourierSatchel(count: entry.box.items.count, avatar: false).frame(width: 48, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                  Text(entry.box.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                  Text("\(entry.box.items.count) piece\(entry.box.items.count == 1 ? "" : "s") · expires \(entry.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 10)).foregroundStyle(Ink.secondary)
                }
                Spacer(minLength: 4)
                Button("Restore") { store.restoreFromBin(entry.id) }.buttonStyle(.bordered)
                Button {
                  removing = entry.id
                  confirmRemoval = true
                } label: { Image(systemName: "trash").frame(width: 24, height: 28) }
                  .buttonStyle(.plain).help("Delete parcel permanently")
                  .accessibilityLabel("Delete \(entry.box.name) permanently")
              }.padding(10).background(Ink.canvas, in: RoundedRectangle(cornerRadius: 12))
            }
          }
        }
      }
      HStack {
        Text("\(store.trashedBoxes.count) parcel\(store.trashedBoxes.count == 1 ? "" : "s") in Bin")
          .font(.system(size: 11)).foregroundStyle(Ink.secondary)
        Spacer()
        Button("Empty Bin…", role: .destructive) { removing = nil; confirmRemoval = true }
          .disabled(store.trashedBoxes.isEmpty || store.busy)
      }
    }.padding(24).frame(width: 590, height: 460).background(Ink.paper).foregroundStyle(Ink.text)
      .disabled(store.busy || store.phase == .receiving)
      .onAppear { store.purgeExpiredBin() }
      .alert(removing == nil ? "Empty the Bin permanently?" : "Delete this parcel permanently?",
             isPresented: $confirmRemoval) {
        Button(removing == nil ? "Empty Bin" : "Delete permanently", role: .destructive) {
          store.emptyBin(removing)
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("These parcel entries cannot be restored afterwards. Your original files and saved exports will not be deleted.")
      }
  }
}

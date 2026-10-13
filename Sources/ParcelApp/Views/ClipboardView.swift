import AppKit
import SwiftUI

/// Clipboard history panel: searchable, pinnable recent clips.
/// Password-manager apps and concealed pasteboard types are never captured.
struct ClipboardView: View {
  @StateObject private var history = ClipboardHistory.shared
  @EnvironmentObject private var store: ParcelStore
  @State private var query = ""
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("CLIPBOARD").font(.system(size: 9, weight: .semibold)).tracking(2)
            .foregroundStyle(Ink.secondary)
          Text("Recent copies, kept on this Mac")
            .font(.system(size: 11)).foregroundStyle(Ink.secondary)
        }
        Spacer()
        Toggle("Watch clipboard", isOn: $history.isEnabled)
          .font(.system(size: 11)).toggleStyle(.switch).controlSize(.small)
      }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)
      HStack {
        Image(systemName: "magnifyingglass").foregroundStyle(Ink.secondary)
        TextField("Search clips", text: $query).textFieldStyle(.plain)
      }.padding(8).background(Ink.cream, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 20).padding(.bottom, 8)
      if filtered.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "doc.on.clipboard").font(.system(size: 28))
            .foregroundStyle(Ink.secondary.opacity(0.6))
          Text("Nothing here yet")
            .font(.system(size: 13, weight: .medium))
          Text("Copy some text or an image and it will appear here.\nPassword managers are never watched.")
            .font(.system(size: 11)).foregroundStyle(Ink.secondary)
            .multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 8) {
            ForEach(filtered) { entry in
              ClipboardRow(entry: entry)
            }
          }.padding(.horizontal, 20).padding(.bottom, 12)
        }
      }
      HStack {
        Image(systemName: "lock.shield").font(.system(size: 11)).foregroundStyle(Ink.moss)
        Text("On this Mac only. Pinned clips are kept; the rest roll off.")
          .font(.system(size: 10)).foregroundStyle(Ink.secondary)
        Spacer()
        Button("Clear") { history.clearUnpinned() }
          .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Ink.secondary)
      }.padding(.horizontal, 20).padding(.vertical, 10)
    }.frame(width: 380, height: 480)
      .background(Ink.paper).foregroundStyle(Ink.text)
  }
  private var filtered: [ClipboardHistory.Entry] {
    guard !query.isEmpty else { return history.entries }
    return history.entries.filter {
      ($0.text ?? "").localizedCaseInsensitiveContains(query)
    }
  }
}

private struct ClipboardRow: View {
  @StateObject private var history = ClipboardHistory.shared
  let entry: ClipboardHistory.Entry
  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      if let data = entry.imagePNG, let nsImage = NSImage(data: data) {
        Image(nsImage: nsImage).resizable().aspectRatio(contentMode: .fit)
          .frame(width: 44, height: 44).cornerRadius(8)
      } else {
        Image(systemName: "doc.plaintext").font(.system(size: 16))
          .foregroundStyle(Ink.secondary).frame(width: 44, height: 44)
          .background(Ink.cream, in: RoundedRectangle(cornerRadius: 8))
      }
      VStack(alignment: .leading, spacing: 3) {
        Text(entry.preview).font(.system(size: 12)).lineLimit(2)
        Text(entry.capturedAt, style: .relative).font(.system(size: 10))
          .foregroundStyle(Ink.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading)
      if entry.isPinned {
        Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Ink.moss)
      }
      Menu {
        Button("Copy") { history.copy(entry) }
        Button(entry.isPinned ? "Unpin" : "Pin") { history.togglePin(entry.id) }
        Divider()
        Button("Delete", role: .destructive) { history.remove(entry.id) }
      } label: {
        Image(systemName: "ellipsis.circle").font(.system(size: 14))
      }.menuStyle(.borderlessButton).frame(width: 22)
    }.padding(10)
      .background(Ink.canvas, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ink.line.opacity(0.7), lineWidth: 1))
      .onTapGesture { history.copy(entry) }
  }
}

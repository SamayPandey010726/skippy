import AppKit
import SwiftUI

struct CompactParcelView: View {
  @EnvironmentObject private var store: ParcelStore
  @State private var pinned = AppController.shared.isPinned()
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        BrandMark()
        Spacer()
        Button {
          pinned.toggle()
          AppController.shared.setPinned(pinned)
        } label: {
          Image(systemName: pinned ? "pin.fill" : "pin").font(.system(size: 11))
        }.buttonStyle(QuietButtonStyle()).help(
          pinned ? "Unpin from the screen edge" : "Pin to the screen edge")
        Button {
          AppController.shared.openWorkbench()
        } label: {
          Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11))
        }.buttonStyle(QuietButtonStyle()).help("Open packing table")
      }.padding(.horizontal, 25).padding(.top, 31)
      HStack {
        Text(store.current?.name ?? "My parcel").font(.system(size: 11)).foregroundStyle(
          Ink.secondary
        ).lineLimit(1)
        Spacer()
        Button {
          store.addFilesPanel()
        } label: {
          Image(systemName: "plus")
        }.buttonStyle(QuietButtonStyle()).disabled(store.busy)
      }.padding(.horizontal, 25).padding(.top, 5)
      ParcelHero(compact: true, shelfMode: true).padding(.horizontal, 13)
      if store.items.isEmpty {
        Text("A little box, wherever you work.").font(.system(size: 11)).foregroundStyle(
          Ink.secondary
        ).padding(.top, 10)
      } else {
        ScrollView {
          VStack(spacing: 6) {
            ForEach(store.items.prefix(4)) { item in
              HStack(spacing: 10) {
                FileThumbnail(url: item.effectiveURL, size: 25)
                Text(item.effectiveName).font(.system(size: 11)).lineLimit(1)
                Spacer()
                DragOutSurface(
                  urls: store.canExport ? [item.effectiveURL] : [], enabled: !store.busy,
                  tap: { QuickLookController.shared.show([item.effectiveURL]) }
                ).frame(width: 24, height: 26).overlay(
                  Image(systemName: "hand.draw").font(.system(size: 10)).foregroundStyle(
                    Ink.secondary
                  ).allowsHitTesting(false))
              }.padding(9).background(Ink.canvas, in: RoundedRectangle(cornerRadius: 9))
            }
          }
        }.frame(maxHeight: 143).padding(.horizontal, 25)
      }
      Spacer(minLength: 8)
      HStack {
        Image(systemName: "checkmark.shield")
        Text(store.notice ?? "Originals are always safe.").lineLimit(1)
        Spacer()
        Button {
          store.shareViaWhatsApp()
        } label: {
          Image(systemName: "message").font(.system(size: 11))
        }.buttonStyle(QuietButtonStyle()).help("Send via WhatsApp").disabled(
          !store.ready || store.busy || !store.canExport)
        ShareButton(items: store.shareItems(), enabled: store.canExport && !store.busy).frame(
          width: 73, height: 24)
      }.font(.system(size: 10)).foregroundStyle(Ink.secondary).padding(.horizontal, 22).padding(
        .vertical, 15)
    }.background(Ink.paper).preferredColorScheme(.light)
      .alert(
        "Something needs a little care",
        isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
      ) {
        Button("OK", role: .cancel) { store.error = nil }
      } message: {
        Text(store.error ?? "")
      }
  }
}

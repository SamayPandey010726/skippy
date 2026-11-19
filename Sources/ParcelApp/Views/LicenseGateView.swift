import AppKit
import SwiftUI

struct LicenseGateView: View {
  @EnvironmentObject private var store: ParcelStore
  @State private var licence = ""
  @State private var message: String?
  @StateObject private var skins = SkinStore.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        BrandMark()
        Spacer()
        Text("ACTIVATION").font(.system(size: 9, weight: .semibold)).tracking(1.6)
          .foregroundStyle(Ink.secondary)
      }
      VStack(alignment: .leading, spacing: 9) {
        Text("Parcel needs a licence.").font(.custom(Ink.serif, size: 30)).foregroundStyle(Ink.green)
        Text("The shelf, clipboard, watched folders and file tools stay off until a signed licence is verified on this Mac.")
          .font(.system(size: 12)).foregroundStyle(Ink.secondary).lineSpacing(4)
      }
      VStack(alignment: .leading, spacing: 8) {
        Text("THIS MAC'S ID").font(.system(size: 9, weight: .semibold)).tracking(1.2)
          .foregroundStyle(Ink.secondary)
        HStack {
          Text(MachineID.current).font(.system(size: 10, design: .monospaced)).lineLimit(1)
            .truncationMode(.middle)
          Spacer()
          Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(MachineID.current, forType: .string)
            message = "Mac ID copied."
          }.buttonStyle(QuietButtonStyle())
        }.padding(11).background(Ink.canvas, in: RoundedRectangle(cornerRadius: 10))
      }
      TextEditor(text: $licence).font(.system(size: 10, design: .monospaced))
        .scrollContentBackground(.hidden).frame(height: 105).padding(10)
        .background(Ink.canvas, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Ink.line))
        .accessibilityLabel("Parcel licence")
      HStack {
        Button("Activate licence") { activate() }.buttonStyle(MossButtonStyle())
          .disabled(licence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if let checkoutURL {
          Button("Get a licence") { NSWorkspace.shared.open(checkoutURL) }
            .buttonStyle(MossButtonStyle(secondary: true))
        }
        Spacer()
        Button("Quit") { NSApp.terminate(nil) }.buttonStyle(QuietButtonStyle())
      }
      if let message { Text(message).font(.system(size: 11)).foregroundStyle(Ink.secondary) }
    }.padding(30).background(Ink.paper).foregroundStyle(Ink.text)
      .preferredColorScheme(skins.skin == .night ? .dark : .light)
  }

  private var checkoutURL: URL? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "ParcelCheckoutURL") as? String,
      let url = URL(string: value), url.scheme == "https" else { return nil }
    return url
  }

  private func activate() {
    do {
      try LicenseManager.shared.activate(licence)
      store.refreshLicense()
      message = "Licence verified. Parcel is ready."
    } catch { message = error.localizedDescription }
  }
}

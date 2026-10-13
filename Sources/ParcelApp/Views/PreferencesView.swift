import AppKit
import ServiceManagement
import SwiftUI

struct PreferencesView: View {
  @EnvironmentObject private var store: ParcelStore
  @State private var tab = 0
  @State private var licenceText = ""
  @State private var message: String?
  private var saveLocationLabel: String {
    if let path = store.preferences.exportFolder {
      return (path as NSString).abbreviatingWithTildeInPath
    }
    return "~/Downloads"
  }
  private func chooseSaveLocation() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.prompt = "Choose"
    if let path = store.preferences.exportFolder {
      panel.directoryURL = URL(fileURLWithPath: path)
    }
    if panel.runModal() == .OK, let url = panel.url {
      store.preferences.exportFolder = url.path
      store.savePreferences()
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        BrandMark()
        Spacer()
        Text("PREFERENCES").font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(
          Ink.secondary)
      }
      Picker("Preferences", selection: $tab) {
        Text("Everyday care").tag(0)
        Text("Your licence").tag(1)
        Text("About").tag(2)
      }.pickerStyle(.segmented)
      if tab == 0 { general } else if tab == 1 { licence } else { about }
      Spacer(minLength: 0)
      if let message { Text(message).font(.system(size: 11)).foregroundStyle(Ink.secondary) }
    }.padding(30).background(Ink.paper).preferredColorScheme(.light)
  }
  private var general: some View {
    VStack(alignment: .leading, spacing: 19) {
      Text("Just the way you like it.").font(.custom(Ink.serif, size: 24)).foregroundStyle(
        Ink.green)
      Toggle("Clean .DS_Store and __MACOSX from ZIPs", isOn: $store.preferences.cleanMetadata)
        .disabled(store.busy)
      Toggle("Include a readable contents list", isOn: $store.preferences.includeManifest).disabled(
        store.busy)
      Toggle("Add the date to parcel filenames", isOn: $store.preferences.appendDate).disabled(
        store.busy)
      Toggle("Soft sound when a parcel is sealed", isOn: $store.preferences.playSounds)
      Toggle(
        "Open Parcel at login",
        isOn: Binding(
          get: { store.preferences.launchAtLogin },
          set: { value in
            do {
              if value {
                try SMAppService.mainApp.register()
              } else {
                try SMAppService.mainApp.unregister()
              }
              store.preferences.launchAtLogin = value
              store.preferences.save()
            } catch {
              message = "Login preference could not be changed: \(error.localizedDescription)"
            }
          }))
      Divider().overlay(Ink.line)
      HStack {
        Text("Drop popup shortcut")
        Spacer()
        Text("Control + Option + P").font(.system(size: 11, design: .monospaced)).foregroundStyle(
          Ink.moss)
      }
      Toggle(
        "Pop out the drop square when dragging files",
        isOn: Binding(
          get: { DropPopupController.shared.isEnabled },
          set: { DropPopupController.shared.isEnabled = $0 })
      )
      Text(
        "A little square appears on screen the moment a file drag begins. Drag its top grip to park it anywhere — it remembers its spot."
      ).font(.system(size: 11)).foregroundStyle(Ink.secondary).lineSpacing(4)
      Divider().overlay(Ink.line)
      HStack {
        Text("Default save location")
        Spacer()
        Text(saveLocationLabel).font(.system(size: 11)).foregroundStyle(Ink.secondary).lineLimit(
          1
        ).truncationMode(.middle).frame(maxWidth: 220, alignment: .trailing)
        Button("Choose…") { chooseSaveLocation() }.buttonStyle(QuietButtonStyle())
      }
      Text("“Save parcel” puts the packed file here without asking. Defaults to Downloads.")
        .font(.system(size: 11)).foregroundStyle(Ink.secondary).lineSpacing(4)
      Text(
        "Motion follows your macOS Reduce Motion setting. Sounds start off. All file preparation stays on your Mac."
      ).font(.system(size: 11)).foregroundStyle(Ink.secondary).lineSpacing(4)
      Button("Clean unused app copies") { store.cleanUnusedCopies() }
        .buttonStyle(QuietButtonStyle()).disabled(store.busy || store.needsLibraryRecovery)
      Text(
        "Only unreferenced app copies older than a day are removed. ZIPs saved outside Parcel and original local files are untouched."
      )
      .font(.system(size: 10)).foregroundStyle(Ink.secondary)
      Button("Show local parcel library") { NSWorkspace.shared.open(StoragePaths.root) }
        .buttonStyle(QuietButtonStyle())
    }.font(.system(size: 12)).toggleStyle(.checkbox)
      .onChange(of: store.preferences) { _, _ in store.savePreferences() }
  }
  private var licence: some View {
    VStack(alignment: .leading, spacing: 17) {
      Text(store.license.label).font(.custom(Ink.serif, size: 25)).foregroundStyle(Ink.green)
      if case .appStore = store.license {
        Text("You're covered by your App Store purchase — no licence key needed.").font(
          .system(size: 12)
        ).foregroundStyle(Ink.secondary).lineSpacing(4)
      } else if case .licensed(let name) = store.license {
        Text("Thank you, \(name). Your parcel is yours to keep.").font(.system(size: 12))
          .foregroundStyle(Ink.secondary)
      } else {
        Text("Paste your complete licence below. Verification happens on this Mac.").font(
          .system(size: 12)
        ).foregroundStyle(Ink.secondary)
        TextEditor(text: $licenceText).font(.system(size: 11, design: .monospaced))
          .scrollContentBackground(.hidden).frame(height: 105).padding(10).background(
            Ink.canvas, in: RoundedRectangle(cornerRadius: 9)
          ).overlay(RoundedRectangle(cornerRadius: 9).stroke(Ink.line, lineWidth: 1))
        HStack {
          Button("Activate licence") {
            do {
              try LicenseManager.shared.activate(licenceText)
              store.refreshLicense()
              message = "Licence saved. Thank you!"
            } catch { message = error.localizedDescription }
          }.buttonStyle(MossButtonStyle()).disabled(
            licenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          if let s = Bundle.main.object(forInfoDictionaryKey: "ParcelCheckoutURL") as? String,
            let url = URL(string: s), url.scheme == "https"
          {
            Button("Get Parcel") { NSWorkspace.shared.open(url) }.buttonStyle(
              MossButtonStyle(secondary: true))
          }
        }
      }
      if store.license != .development {
        Divider().overlay(Ink.line)
        VStack(alignment: .leading, spacing: 8) {
          Text("This Mac's ID").font(.system(size: 11, weight: .medium))
          HStack {
            Text(MachineID.current).font(.system(size: 10, design: .monospaced)).foregroundStyle(
              Ink.secondary
            ).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Copy") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(MachineID.current, forType: .string)
              Toaster.shared.copied("Mac ID")
              message =
                "Mac ID copied — send it with your order and we'll issue a licence locked to this Mac."
            }.buttonStyle(QuietButtonStyle())
          }
          Text("Direct licences are locked to one Mac, so a key can't be shared between people.")
            .font(.system(size: 11)).foregroundStyle(Ink.secondary).lineSpacing(4)
        }
      }
      Text(
        "Your existing parcels remain available after the trial. A licence unlocks preparation, packaging and sharing."
      ).font(.system(size: 11)).foregroundStyle(Ink.secondary).lineSpacing(4)
    }
  }
  private var about: some View {
    VStack(alignment: .leading, spacing: 17) {
      HStack {
        ParcelIllustration(sealed: true, count: 3, bounce: 0).frame(width: 170, height: 140)
        VStack(alignment: .leading, spacing: 7) {
          Text("Gather. Prepare.\nPack. Send.").font(.custom(Ink.serif, size: 24)).foregroundStyle(
            Ink.green)
          Text("Parcel 1.0.0").font(.system(size: 11)).foregroundStyle(Ink.secondary)
        }
      }
      Text(
        "A little box for the pieces of your day. Original artwork and native file handling, made to feel calm and useful."
      ).font(.system(size: 12)).foregroundStyle(Ink.secondary).lineSpacing(4)
      Text("ZIPFoundation © Thomas Zoechling · MIT licence").font(.system(size: 10))
        .foregroundStyle(Ink.secondary)
      Button("Third-party acknowledgements") {
        if let u = ResourceLocator.url("Acknowledgements", extension: "txt") {
          NSWorkspace.shared.open(u)
        }
      }.buttonStyle(QuietButtonStyle())
      if store.license == .development {
        Text(
          "This is a developer build. Licensing is disabled until a production build is configured."
        ).font(.system(size: 11)).foregroundStyle(Ink.secondary)
      }
    }
  }
}

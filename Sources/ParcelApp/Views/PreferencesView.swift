import AppKit
import ParcelCore
import ServiceManagement
import SwiftUI

struct PreferencesView: View {
  @EnvironmentObject private var store: ParcelStore
  @ObservedObject private var quiver = SkippyQuiver.shared
  @State private var tab = 0
  @State private var licenceText = ""
  @State private var message: String?
  @StateObject private var skins = SkinStore.shared
  @ObservedObject private var courier = DropPopupController.shared
  @ObservedObject private var watches = WatchedFolders.shared
  @ObservedObject private var presets = TransformPresetStore.shared
  @ObservedObject private var history = RecentActionStore.shared
  @ObservedObject private var spotlight = SpotlightIndexer.shared
  @ObservedObject private var shortcuts = GlobalShortcutManager.shared
  @ObservedObject private var courierShortcuts = CourierShortcutStore.shared
  @ObservedObject private var notchWidgets = NotchWidgetStore.shared
  init(initialTab: Int = 0) {
    _tab = State(initialValue: initialTab)
  }
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
      HStack(spacing: 6) {
        settingsTab("Everyday", value: 0)
        settingsTab("Shortcuts", value: 1)
        settingsTab("Automation", value: 2)
        settingsTab("Licence", value: 3)
        settingsTab("About", value: 4)
      }.padding(4).background(Ink.cream, in: RoundedRectangle(cornerRadius: 10))
      ScrollView {
        Group {
          if tab == 0 { general }
          else if tab == 1 { keyboardShortcuts }
          else if tab == 2 { automation }
          else if tab == 3 { licence }
          else { about }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 8)
      }
      Spacer(minLength: 0)
      if let message { Text(message).font(.system(size: 11)).foregroundStyle(Ink.secondary) }
    }.padding(30).background(Ink.paper).foregroundStyle(Ink.text)
      .preferredColorScheme(skins.skin == .night ? .dark : .light)
  }
  private func settingsTab(_ title: String, value: Int) -> some View {
    Button {
      withAnimation(Motion.layoutRelayout) { tab = value }
    } label: {
      Text(title).font(.system(size: 11, weight: tab == value ? .semibold : .regular))
        .foregroundStyle(tab == value ? Color.white : Ink.text)
        .frame(maxWidth: .infinity).padding(.vertical, 7)
        .background(tab == value ? Ink.green : Color.clear, in: RoundedRectangle(cornerRadius: 7))
    }.buttonStyle(.plain).accessibilityAddTraits(tab == value ? .isSelected : [])
  }
  private var keyboardShortcuts: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Everything, without the mouse.").font(.custom(Ink.serif, size: 24)).foregroundStyle(Ink.green)
      Text("Open Skippy, then use these commands anywhere in the notch. Copy sends the focused file or packed ZIP; Paste adds files, images, links or text to your single parcel.")
        .font(.system(size: 11)).foregroundStyle(Ink.secondary).lineSpacing(3)
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("Open Skippy anywhere").font(.system(size: 13, weight: .semibold))
            Text("In Finder or another app, this also imports the current selection.")
              .font(.system(size: 10)).foregroundStyle(Ink.secondary)
          }
          Spacer()
          ShortcutRecorder(shortcut: shortcuts.shortcut, onRecord: shortcuts.update)
            .frame(width: 108, height: 26)
        }
        Text(shortcuts.message).font(.system(size: 10)).foregroundStyle(Ink.moss)
      }.padding(14).background(Ink.canvas.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Skippy notch commands").font(.system(size: 13, weight: .semibold))
          Spacer()
          Button("Reset all") { courierShortcuts.resetAll() }.font(.system(size: 10))
        }
        ForEach(CourierCommand.allCases) { command in
          HStack {
            Text(command.title).font(.system(size: 11))
            Spacer()
            CourierShortcutRecorder(command: command, binding: courierShortcuts.binding(for: command),
              onRecord: courierShortcuts.update).frame(width: 92, height: 24)
          }
          if command != CourierCommand.allCases.last { Divider().opacity(0.45) }
        }
      }.padding(14).background(Ink.canvas.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
      HStack {
        Button("Replay beginner tutorial") { AppController.shared.showTutorial() }.buttonStyle(QuietButtonStyle())
        Spacer()
      }
    }.font(.system(size: 12))
  }
  private var automation: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Fast paths, kept local.").font(.custom(Ink.serif, size: 24)).foregroundStyle(Ink.green)
      Text("Presets appear in Prepare copies. Edit names and settings here; every conversion remains non-destructive.")
        .font(.system(size: 11)).foregroundStyle(Ink.secondary)
      Text("Image presets").font(.system(size: 13, weight: .semibold))
      ForEach(presets.imagePresets) { preset in
        imagePresetEditor(preset)
      }
      Button("Add current image settings") { presets.addImage(name: "Custom image", recipe: store.recipe) }
        .buttonStyle(QuietButtonStyle())
      Divider()
      Text("Video presets").font(.system(size: 13, weight: .semibold))
      ForEach(presets.videoPresets) { preset in
        videoPresetEditor(preset)
      }
      Button("Add current video settings") { presets.addVideo(name: "Custom video", recipe: store.videoRecipe) }
        .buttonStyle(QuietButtonStyle())
      Divider()
      Text("Recent actions").font(.system(size: 13, weight: .semibold))
      if history.actions.isEmpty {
        Text("Your five most recent actions will appear beside Quick Actions and reorder compatible Shift-drag conversions.")
          .font(.system(size: 11)).foregroundStyle(Ink.secondary)
      } else {
        ForEach(history.actions.prefix(5)) { action in
          Label("\(action.title) · \(action.useCount)×", systemImage: action.symbol)
            .font(.system(size: 11)).foregroundStyle(Ink.secondary)
        }
      }
      Divider()
      Text("Shortcuts and Spotlight").font(.system(size: 13, weight: .semibold))
      Toggle("Index parcel and file names in Spotlight", isOn: $spotlight.enabled)
      Text("Skippy publishes actions for opening the notch, adding files, packing, and searching. File names are indexed only in your Mac's private Spotlight index.")
        .font(.system(size: 11)).foregroundStyle(Ink.secondary)
    }.font(.system(size: 12))
  }

  private func imagePresetEditor(_ preset: ImageTransformPreset) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        TextField("Preset name", text: Binding(
          get: { preset.name }, set: { var next = preset; next.name = $0; presets.update(next) }))
          .textFieldStyle(.plain).foregroundStyle(Ink.text).padding(.horizontal, 8).padding(.vertical, 6)
          .background(Ink.paper, in: RoundedRectangle(cornerRadius: 7))
          .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.line))
        Button(role: .destructive) { presets.removeImage(preset.id) } label: { Image(systemName: "trash") }
          .buttonStyle(.borderless).help("Delete preset")
      }
      HStack {
        Picker("Format", selection: Binding(
          get: { preset.recipe.format }, set: { var next = preset; next.recipe.format = $0; presets.update(next) })) {
          ForEach(ImageFormat.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        Picker("Maximum edge", selection: Binding(
          get: { preset.recipe.maximumDimension }, set: { var next = preset; next.recipe.maximumDimension = $0; presets.update(next) })) {
          Text("Original").tag(0); Text("1200").tag(1200); Text("1600").tag(1600)
          Text("2400").tag(2400); Text("3200").tag(3200); Text("4000").tag(4000)
        }
      }
      HStack {
        Text("Quality \(Int(preset.recipe.quality * 100))%").frame(width: 82, alignment: .leading)
        Slider(value: Binding(
          get: { preset.recipe.quality }, set: { var next = preset; next.recipe.quality = $0; presets.update(next) }),
          in: 0.1...1).disabled(preset.recipe.format == .png)
      }
    }.padding(10).background(Ink.canvas, in: RoundedRectangle(cornerRadius: 10))
  }

  private func videoPresetEditor(_ preset: VideoTransformPreset) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        TextField("Preset name", text: Binding(
          get: { preset.name }, set: { var next = preset; next.name = $0; presets.update(next) }))
          .textFieldStyle(.plain).foregroundStyle(Ink.text).padding(.horizontal, 8).padding(.vertical, 6)
          .background(Ink.paper, in: RoundedRectangle(cornerRadius: 7))
          .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.line))
        Button(role: .destructive) { presets.removeVideo(preset.id) } label: { Image(systemName: "trash") }
          .buttonStyle(.borderless).help("Delete preset")
      }
      HStack {
        Picker("Maximum edge", selection: Binding(
          get: { preset.maximumDimension }, set: { var next = preset; next.maximumDimension = $0; presets.update(next) })) {
          ForEach([480, 720, 1280, 1920, 3840], id: \.self) { Text("\($0) px").tag($0) }
        }
        Picker("Quality", selection: Binding(
          get: { preset.quality }, set: { var next = preset; next.quality = $0; presets.update(next) })) {
          ForEach(VideoQuality.allCases) { Text($0.rawValue.capitalized).tag($0) }
        }
      }
    }.padding(10).background(Ink.canvas, in: RoundedRectangle(cornerRadius: 10))
  }
  private var general: some View {
    VStack(alignment: .leading, spacing: 19) {
      Text("Just the way you like it.").font(.custom(Ink.serif, size: 24)).foregroundStyle(
        Ink.green)
      VStack(alignment: .leading, spacing: 12) {
        Label("Appearance", systemImage: "paintpalette").font(.system(size: 13, weight: .semibold))
        HStack {
          Text("Universal interface size")
          Spacer()
          Text("\(Int(courier.interfaceScale * 100))%").monospacedDigit()
          Button("Reset") { courier.interfaceScale = 1 }.font(.system(size: 10))
        }
        Slider(value: Binding(get: { Double(courier.interfaceScale) }, set: { courier.interfaceScale = CGFloat($0) }),
          in: 0.75...1.5, step: 0.05).accessibilityLabel("Universal interface size")
        SkinPickerRow()
        Picker("Attach quiver to", selection: $quiver.surface) {
          ForEach(QuiverSurface.allCases) { Text($0.rawValue).tag($0) }
        }
        Text("Hover to unfold pinned arrows. Click an arrow to open its panel. Drag the floating mark to a screen edge to attach it. In the Dock, click to open or secondary-click for arrows.")
          .font(.caption).foregroundStyle(.secondary)
        Picker("Collapse after", selection: Binding(get: { courier.idleTimeout }, set: { courier.idleTimeout = $0 })) {
          Text("5 sec").tag(TimeInterval(5)); Text("10 sec").tag(TimeInterval(10))
          Text("30 sec").tag(TimeInterval(30)); Text("1 min").tag(TimeInterval(60)); Text("Never").tag(TimeInterval(0))
        }
      }.padding(14).background(Ink.canvas.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
      VStack(alignment: .leading, spacing: 9) {
        HStack {
          Label("Quiver arrows", systemImage: "square.grid.2x2").font(.system(size: 13, weight: .semibold))
          Spacer()
          Button("Reset layout", action: notchWidgets.reset).font(.system(size: 10))
        }
        Text("Drag widgets to rearrange them. Every feature supports Small, Tall, Wide, Large and Full-page sizes. Scrolling snaps one complete page at a time.")
          .font(.system(size: 10)).foregroundStyle(Ink.secondary)
        ForEach(notchWidgets.widgets) { widget in
          HStack(spacing: 8) {
            Image(systemName: widget.kind.module.symbol).foregroundStyle(Ink.green).frame(width: 18)
            Text(widget.kind.module.title).font(.system(size: 11)).frame(width: 86, alignment: .leading)
            Picker("Size", selection: Binding(
              get: { widget.size }, set: { notchWidgets.resize(widget.kind, to: $0) })) {
              ForEach(NotchWidgetSize.allCases) { Text($0.label).tag($0) }
            }.labelsHidden().frame(width: 145)
            Spacer()
            Toggle("Pinned", isOn: Binding(
              get: { widget.pinned }, set: { _ in notchWidgets.togglePinned(widget.kind) }))
              .toggleStyle(.checkbox).font(.system(size: 10))
          }
        }
      }.padding(14).background(Ink.canvas.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
      VStack(alignment: .leading, spacing: 9) {
        Label("Parcel file tray", systemImage: "shippingbox").font(.system(size: 13, weight: .semibold))
        Toggle("Clean .DS_Store and __MACOSX from ZIPs", isOn: $store.preferences.cleanMetadata).disabled(store.busy)
        Toggle("Include a readable contents list", isOn: $store.preferences.includeManifest).disabled(store.busy)
        Toggle("Add the date to parcel filenames", isOn: $store.preferences.appendDate).disabled(store.busy)
        Toggle("Soft sound when a parcel is sealed", isOn: $store.preferences.playSounds)
        Toggle("Self-cleaning shelf: clear unpinned items older than a day", isOn: $store.preferences.autoClearStale).disabled(store.busy)
        Toggle("Show occasional shortcut and gesture tips", isOn: Binding(
          get: { UserDefaults.standard.object(forKey: "parcel.showTips") as? Bool ?? true },
          set: { UserDefaults.standard.set($0, forKey: "parcel.showTips") }))
      }.padding(14).background(Ink.canvas.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
      VStack(alignment: .leading, spacing: 10) {
        Label("Packing defaults", systemImage: "archivebox").font(.system(size: 13, weight: .semibold))
        Text("Dragging a parcel name packs with these settings automatically.")
          .font(.system(size: 10)).foregroundStyle(Ink.secondary)
        HStack(spacing: 6) {
          ForEach(PackFormat.availableCases.filter(\.isUsable), id: \.self) { format in
            preferencePill(format.label, selected: store.packaging.format == format) {
              store.packaging.format = format
            }
          }
        }
        HStack(spacing: 6) {
          ForEach(PackStrength.allCases, id: \.self) { strength in
            preferencePill(strength.label, selected: store.packaging.strength == strength) {
              store.packaging.strength = strength
            }
          }
        }
        Text(store.packaging.strength.hint).font(.system(size: 10)).foregroundStyle(Ink.secondary)
        Toggle("Compress archive contents", isOn: $store.packaging.compressArchive)
        Toggle("Save packed parcels to Desktop", isOn: $store.packaging.saveToDesktop)
      }.padding(14).background(Ink.canvas.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
        .disabled(store.busy).onChange(of: store.packaging) { _, _ in store.savePackaging() }
      Text("The quiver holds your pinned arrows. The File Shelf keeps temporary files ready to drag into another app.")
        .font(.system(size: 11)).foregroundStyle(Ink.secondary)
      Divider()
      Text("Finder and sharing").font(.system(size: 13, weight: .semibold))
      Toggle("Shift-drag conversion ribbon", isOn: Binding(
        get: { courier.shiftConvertEnabled }, set: { courier.shiftConvertEnabled = $0 }))
      Picker("Conversion HUD", selection: Binding(
        get: { courier.shiftConvertAppearance }, set: { courier.shiftConvertAppearance = $0 })) {
        ForEach(QuickConvertAppearance.allCases) { Text($0.label).tag($0) }
      }.pickerStyle(.segmented).disabled(!courier.shiftConvertEnabled)
      Text("Start dragging image, PDF, video, document, or spreadsheet files, then hold Shift. Drop onto a relevant output in the compact ribbon. The current format is hidden; every result is saved in Parcel.")
        .font(.system(size: 11)).foregroundStyle(Ink.secondary)
      Text("Right-click selected files or folders in Finder → Services → Send to Skippy. macOS controls which apps expose Services. If hidden, enable it in System Settings → Keyboard → Keyboard Shortcuts → Services.")
        .font(.system(size: 11)).foregroundStyle(Ink.secondary)
      Divider()
      Text("Watched folders").font(.system(size: 13, weight: .semibold))
      Text("New top-level files are referenced in the chosen parcel after a quiet period. No files are moved, deleted or uploaded. Existing files are not imported; partial downloads are ignored.")
        .font(.system(size: 11)).foregroundStyle(Ink.secondary)
      Text("New files go to \(store.current?.name ?? "your parcel").")
        .font(.system(size: 11, weight: .medium))
      Button("Watch a folder…") {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Watch new files"
        if panel.runModal() == .OK, let folder = panel.url, let parcelID = store.current?.id {
          watches.add(folder: folder, parcelID: parcelID)
        }
      }.disabled(store.current == nil || store.busy)
      HStack {
        Button("Watch Downloads") {
          if let parcelID = store.current?.id,
            let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            watches.add(folder: folder, parcelID: parcelID, rule: .downloads)
          }
        }
        Button("Watch screenshots") {
          if let parcelID = store.current?.id,
            let folder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            watches.add(folder: folder, parcelID: parcelID, rule: .screenshots)
          }
        }
      }.disabled(store.current == nil || store.busy)
      ForEach(watches.folders) { folder in
        HStack {
          Toggle("\((folder.path as NSString).lastPathComponent) · \(folder.rule.label)",
            isOn: Binding(get: { folder.enabled }, set: { watches.setEnabled(folder.id, enabled: $0) }))
          Spacer()
          Button("Remove") { watches.remove(folder.id) }.help("Stop watching; files and parcel entries stay untouched")
        }
      }
      if let message = watches.message { Text(message).font(.system(size: 10)).foregroundStyle(Ink.secondary) }
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
      Toggle(
        "Open Skippy when dragging files or images",
        isOn: Binding(
          get: { DropPopupController.shared.isEnabled },
          set: { DropPopupController.shared.isEnabled = $0 })
      )
      Text(
        "The menu-bar island, top-screen edge, file drag, mouse shake, or global shortcut opens Skippy. In Finder, the global shortcut also adds selected files. Tab changes pages; / searches; Command-P packs; Command-S opens Settings; Escape closes."
      ).font(.system(size: 11)).foregroundStyle(Ink.secondary).lineSpacing(4)
      HStack {
        Button("Open Skippy") { DropPopupController.shared.summon() }
          .buttonStyle(QuietButtonStyle())
        Spacer()
      }
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
  private func preferencePill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).font(.system(size: 10, weight: selected ? .semibold : .medium))
        .foregroundStyle(selected ? Color.white : Ink.text)
        .frame(maxWidth: .infinity).padding(.vertical, 7)
        .background(selected ? Ink.green : Ink.paper, in: Capsule())
        .overlay(Capsule().stroke(selected ? Ink.green : Ink.line))
    }.buttonStyle(.plain)
  }
  private var licence: some View {
    VStack(alignment: .leading, spacing: 17) {
      Text(store.license.label).font(.custom(Ink.serif, size: 25)).foregroundStyle(Ink.green)
      if case .licensed(let name) = store.license {
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
            Button("Get Skippy") { NSWorkspace.shared.open(url) }.buttonStyle(
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
          Text("Your licence is signed for one, two or five Mac IDs. Add this ID when your licence is issued.")
            .font(.system(size: 11)).foregroundStyle(Ink.secondary).lineSpacing(4)
        }
      }
      Text(
        "A valid signed licence is required before Parcel's shelf, clipboard and file tools become available."
      ).font(.system(size: 11)).foregroundStyle(Ink.secondary).lineSpacing(4)
    }
  }
  private var about: some View {
    VStack(alignment: .leading, spacing: 17) {
      HStack {
        CourierSatchel(sealed: true, count: 3).frame(width: 170, height: 140)
        VStack(alignment: .leading, spacing: 7) {
          Text("Put down. Navigate.\nPick up.").font(.custom(Ink.serif, size: 24)).foregroundStyle(
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

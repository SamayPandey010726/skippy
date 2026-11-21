import AppKit
import ParcelCore
import ServiceManagement
import SwiftUI

struct PreferencesView: View {
  @EnvironmentObject private var store: ParcelStore
  @ObservedObject private var clipboardHistory = ClipboardHistoryStore.shared
  @ObservedObject private var tools = NotchToolStore.shared
  @ObservedObject private var quiver = SkippyQuiver.shared
  @State private var tab = 0
  @State private var sectionQuery = ""
  @State private var displayedPin: String?
  @ObservedObject private var quickPins = QuickPinStore.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let sections: [(id: Int, title: String, icon: String, keywords: String)] = [
    (0, "General", "gearshape", "appearance icon launch scaling motion hover"),
    (6, "Placement", "macwindow", "edge dock notch floating menu bar"),
    (7, "Pins", "pin", "quick pins arrows widgets apps"),
    (1, "Shortcuts", "keyboard", "keyboard global commands"),
    (8, "Files", "folder", "parcels shelf zip rar conversion archive downloads"),
    (9, "Privacy", "lock.shield", "clipboard finder permissions screen recording accessibility"),
    (2, "Advanced", "slider.horizontal.3", "automation presets spotlight"),
    (3, "Licence", "checkmark.seal", "activation"),
    (4, "About", "info.circle", "version tutorial")
  ]
  @State private var captureAccessMessage: String?
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
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 7) {
          ScoutPreview().frame(width: 23, height: 21)
          Text("Skippy").font(.system(size: 18, weight: .semibold))
        }.padding(.horizontal, 5)
        TextField("Search Settings", text: $sectionQuery)
          .textFieldStyle(.roundedBorder)
          .accessibilityLabel("Search Settings")
        let query = sectionQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = sections.filter { query.isEmpty || ($0.title + " " + $0.keywords).localizedCaseInsensitiveContains(query) }
        ForEach(matches, id: \.id) { section in
          Button {
            tab = section.id
            sectionQuery = ""
          } label: {
            Label(section.title, systemImage: section.icon)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 8).padding(.vertical, 7)
              .background(tab == section.id ? Ink.paleGreen : .clear, in: RoundedRectangle(cornerRadius: 7))
          }.buttonStyle(.plain).accessibilityAddTraits(tab == section.id ? .isSelected : [])
        }
        if matches.isEmpty { Text("No matching sections").font(.caption).foregroundStyle(.secondary) }
        Spacer()
      }.padding(13).frame(width: 172).background(Ink.cream)
      Divider()
      VStack(alignment: .leading, spacing: 0) {
        Text(sections.first(where: { $0.id == tab })?.title ?? "Welcome")
          .font(.title2.weight(.semibold)).padding(19)
          .accessibilityAddTraits(.isHeader)
        Divider()
        ScrollView {
          Group {
            switch tab {
            case 0: general
            case 1: keyboardShortcuts
            case 2: automation
            case 3: licence
            case 5: WelcomeView().frame(maxWidth: .infinity)
            case 6: placement
            case 7: pinSettings
            case 8: files
            case 9: privacy
            default: about
            }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(19)
        }
        .id(tab)
        .transition(.opacity.combined(with: .offset(x: 5)))
        if let message { Text(message).font(.caption).foregroundStyle(Ink.secondary).padding(12) }
      }
    }
    .frame(minWidth: 640, minHeight: 470)
    .background(Ink.paper).foregroundStyle(Ink.text)
    .tint(Ink.green)
    .preferredColorScheme(.light)
    .animation(reduceMotion ? nil : .smooth(duration: 0.23), value: tab)
  }
  private var keyboardShortcuts: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("System-wide").font(.headline)
      Text("These shortcuts work while another app is active. Select a shortcut to change it and press Escape to cancel.")
        .font(.system(size: 11)).foregroundStyle(Ink.secondary).lineSpacing(3)
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("Send selection to Skippy").font(.system(size: 13, weight: .semibold))
            Text("Imports highlighted files or text when access is enabled.")
              .font(.system(size: 10)).foregroundStyle(Ink.secondary)
          }
          Spacer()
          ShortcutRecorder(shortcut: shortcuts.shortcut, onRecord: shortcuts.update)
            .frame(width: 108, height: 26)
        }
        Text(shortcuts.message).font(.system(size: 10)).foregroundStyle(Ink.moss)
      }.padding(14).background(Ink.canvas.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
      VStack(alignment: .leading, spacing: 8) {
        ForEach(WorkspaceShortcut.all) { target in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(target.title)
              if shortcuts.unavailable.contains(target) {
                Text("Unavailable. Choose another key combination.").font(.caption).foregroundStyle(.secondary)
              }
            }
            Spacer()
            ShortcutRecorder(shortcut: shortcuts.binding(for: target), title: target.title + " shortcut") {
              shortcuts.update(target, $0)
            }.frame(width: 114, height: 25)
            Button("Reset") { _ = shortcuts.update(target, target.defaultValue) }
              .accessibilityLabel("Reset " + target.title + " shortcut")
              .disabled(shortcuts.binding(for: target) == target.defaultValue && !shortcuts.unavailable.contains(target))
          }
          Divider()
        }
      }
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("While Skippy has focus").font(.system(size: 13, weight: .semibold))
          Spacer()
          Button("Reset all") { courierShortcuts.resetAll() }.font(.system(size: 10))
        }
        ForEach(CourierCommand.allCases.filter { $0 != .cycleTheme }) { command in
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
  @AppStorage("skippy.hoverLauncher") private var hoverLauncher = true
  @AppStorage("skippy.hoverArrowPreviews") private var hoverArrowPreviews = true

  private var general: some View {
    VStack(alignment: .leading, spacing: 16) {
      LabeledContent("Appearance", value: "Blue-grey")
      Picker("Launcher icon", selection: $quiver.emblem) {
        ForEach(QuiverEmblem.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented)
      Toggle("Open the launcher on hover", isOn: $hoverLauncher)
      Toggle("Preview tools on hover", isOn: $hoverArrowPreviews)
      LabeledContent("Interface size", value: "\(Int(courier.interfaceScale * 100))%")
      Slider(value: Binding(get: { Double(courier.interfaceScale) }, set: { courier.interfaceScale = CGFloat($0) }),
        in: 0.75...1.5, step: 0.05).accessibilityLabel("Interface size")
      Toggle("Open Skippy at login", isOn: Binding(get: { store.preferences.launchAtLogin }, set: { value in
        do {
          if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
          store.preferences.launchAtLogin = value
          store.savePreferences()
        } catch { message = error.localizedDescription }
      }))
      Picker("Close inactive panels after", selection: Binding(get: { courier.idleTimeout }, set: { courier.idleTimeout = $0 })) {
        Text("5 seconds").tag(TimeInterval(5))
        Text("10 seconds").tag(TimeInterval(10))
        Text("30 seconds").tag(TimeInterval(30))
        Text("1 minute").tag(TimeInterval(60))
        Text("Never").tag(TimeInterval(0))
      }
      Text("Animations follow the macOS Reduce Motion setting.").font(.caption).foregroundStyle(.secondary)
    }
  }

  private var placement: some View {
    VStack(alignment: .leading, spacing: 13) {
      Picker("Attach Skippy to", selection: $quiver.surface) {
        ForEach(QuiverSurface.allCases) { Text($0.rawValue).tag($0) }
      }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 95))], spacing: 8) {
        ForEach(QuiverSurface.allCases) { surface in
          Button { quiver.surface = surface } label: {
            VStack(spacing: 8) {
              Image(systemName: placementIcon(surface)).font(.title2)
              Text(surface.rawValue).font(.caption)
            }.frame(maxWidth: .infinity).padding(9)
              .background(quiver.surface == surface ? Ink.paleGreen : Ink.canvas, in: RoundedRectangle(cornerRadius: 9))
          }.buttonStyle(.plain).accessibilityAddTraits(quiver.surface == surface ? .isSelected : [])
        }
      }
      Text("Drag Scout toward an edge to attach it. More opens the same searchable drawer from every placement.")
        .font(.caption).foregroundStyle(.secondary)
      if quiver.surface == .dock && !AXIsProcessTrusted() {
        Button("Allow Dock hover in Accessibility…") {
          let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
          _ = AXIsProcessTrustedWithOptions(options)
        }
      }
    }
  }

  private func placementIcon(_ surface: QuiverSurface) -> String {
    switch surface {
    case .floating: "cursorarrow.square"
    case .left: "sidebar.left"
    case .right: "sidebar.right"
    case .top: "rectangle.topthird.inset.filled"
    case .bottom: "rectangle.bottomthird.inset.filled"
    case .notch: "web.camera"
    case .menu: "menubar.rectangle"
    case .dock: "dock.rectangle"
    }
  }

  private var pinSettings: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Quick Pins").font(.headline)
        Spacer()
        Menu("Add Pin…") {
          ForEach(NotchModule.allCases.filter { $0 != .dashboard && !quickPins.contains($0.id) }) { module in
            Button(module.title) { quickPins.toggle(module.id); displayedPin = module.id }
          }
          ForEach(tools.pinnedApps.filter { !quickPins.contains($0.id) }) { app in
            Button(app.name) { quickPins.toggle(app.id); displayedPin = app.id }
          }
        }.fixedSize()
      }
      let selected = quickPins.pins.first(where: { $0.id == displayedPin }) ?? quickPins.pins.first
      if quickPins.pins.isEmpty {
        Text("Add a tool to place it around Scout.").font(.caption).foregroundStyle(.secondary)
      } else {
        VStack(spacing: 0) {
          ForEach(quickPins.pins) { pin in
            let title = pin.module?.title ?? tools.pinnedApps.first(where: { $0.id == pin.id })?.name ?? pin.id
            HStack(spacing: 7) {
              Button { displayedPin = pin.id } label: {
                HStack {
                  Image(systemName: pin.module?.symbol ?? "app").frame(width: 24, height: 24)
                    .foregroundStyle(Ink.green)
                  Text(title)
                  Spacer()
                }.contentShape(Rectangle())
              }.buttonStyle(.plain).accessibilityAddTraits(selected?.id == pin.id ? .isSelected : [])
              Button { quickPins.move(pin.id, by: -1) } label: { Image(systemName: "arrow.up") }
                .accessibilityLabel("Move " + title + " up").disabled(pin == quickPins.pins.first)
              Button { quickPins.move(pin.id, by: 1) } label: { Image(systemName: "arrow.down") }
                .accessibilityLabel("Move " + title + " down").disabled(pin == quickPins.pins.last)
              Button { quickPins.toggle(pin.id) } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Unpin " + title)
            }.buttonStyle(.borderless).padding(.horizontal, 7).frame(height: 34)
              .background(selected?.id == pin.id ? Ink.paleGreen : .clear)
            if pin != quickPins.pins.last { Divider() }
          }
        }.background(Ink.canvas, in: RoundedRectangle(cornerRadius: 8))
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Ink.line.opacity(0.65)))
      }
      Divider()
      Text("Display").font(.headline)
      Toggle("Show connector lines", isOn: $quickPins.showConnectors)
      Picker("Default visibility", selection: $quickPins.alwaysVisible) {
        Text("On hover").tag(false)
        Text("Always visible").tag(true)
      }.pickerStyle(.segmented)
      if let pin = selected {
        HStack(alignment: .center, spacing: 10) {
          VStack(alignment: .leading, spacing: 9) {
            Picker("Visibility for this pin", selection: Binding(get: { pin.alwaysVisible }, set: { quickPins.setVisibility(pin.id, always: $0) })) {
              Text("Use default").tag(nil as Bool?)
              Text("On hover").tag(false as Bool?)
              Text("Always visible").tag(true as Bool?)
            }
            Picker("Position", selection: Binding(get: { pin.position }, set: { quickPins.position(pin.id, at: $0) })) {
              ForEach(QuickPinPosition.allCases) { slot in Text(slot.title).tag(slot) }
            }
          }
          pinPreview(selected: pin.id)
        }
      }
      Divider()
      Text("Launcher and widgets").font(.headline)
      Button("Add Mac application…", action: tools.choosePinnedApp)
      ForEach(tools.pinnedApps) { app in
        HStack {
          Text(app.name)
          Spacer()
          Button("Remove") {
            if quickPins.contains(app.id) { quickPins.toggle(app.id) }
            tools.unpinApp(app)
          }.accessibilityLabel("Remove " + app.name)
        }
      }
      ForEach(notchWidgets.widgets) { widget in
        HStack {
          Label(widget.kind.module.title, systemImage: widget.kind.module.symbol)
          Spacer()
          Picker("Widget size", selection: Binding(get: { widget.size }, set: { notchWidgets.resize(widget.kind, to: $0) })) {
            ForEach(NotchWidgetSize.allCases) { Text($0.label).tag($0) }
          }.labelsHidden().frame(width: 120)
          Toggle("Launcher", isOn: Binding(get: { widget.pinned }, set: { _ in notchWidgets.togglePinned(widget.kind) }))
        }
      }
      Button("Reset widget layout", action: notchWidgets.reset)
    }
  }

  private func pinPreview(selected: String) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: 13).fill(Ink.cream)
      if quickPins.showConnectors {
        Canvas { context, size in
          let center = CGPoint(x: size.width / 2, y: size.height / 2)
          for pin in quickPins.pins.prefix(3) {
            let offset = pin.position.offset
            var line = Path()
            line.move(to: center)
            line.addLine(to: CGPoint(x: center.x + offset.x * 0.54, y: center.y - offset.y * 0.54))
            context.stroke(line, with: .color(pin.id == selected ? Ink.green : Ink.line), lineWidth: 1)
          }
        }
      }
      ScoutPreview().frame(width: 30, height: 26)
      ForEach(quickPins.pins.prefix(3)) { pin in
        Image(systemName: pin.module?.symbol ?? "app")
          .font(.system(size: 12, weight: .medium)).frame(width: 25, height: 25)
          .background(.white, in: Circle())
          .overlay(Circle().strokeBorder(pin.id == selected ? Ink.green : Ink.line, lineWidth: 1.5))
          .offset(x: pin.position.offset.x * 0.54, y: -pin.position.offset.y * 0.54)
      }
    }.frame(width: 130, height: 130).accessibilityHidden(true)
      .animation(reduceMotion ? nil : .smooth(duration: 0.23), value: quickPins.pins)
  }

  private var files: some View {
    VStack(alignment: .leading, spacing: 17) {
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
      Text("Start dragging image, PDF, video, document, or spreadsheet files, then hold Shift. Drop onto a relevant output in the compact ribbon. The current format is hidden; every result is saved in Skippy.")
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
        "Open Skippy when dragging files or images",
        isOn: Binding(
          get: { DropPopupController.shared.isEnabled },
          set: { DropPopupController.shared.isEnabled = $0 })
      )
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
  private var privacy: some View {
    VStack(alignment: .leading, spacing: 14) {
      Toggle("Keep local clipboard history", isOn: $clipboardHistory.captureEnabled)
      LabeledContent("Screen recording", value: CGPreflightScreenCaptureAccess() ? "Allowed" : "Permission required")
      Button("Request screen recording access…") {
        captureAccessMessage = CGRequestScreenCaptureAccess() ? "Screen recording is allowed." :
          "Allow Skippy in System Settings → Privacy & Security → Screen & System Audio Recording."
      }
      HStack {
        Button("Enable Finder selection…") {
          captureAccessMessage = FinderSelection.hasAccess(request: true)
            ? "Finder selection is enabled." : "Allow Finder access in System Settings → Privacy & Security → Automation."
        }
        Button("Enable selection in other apps…") {
          let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
          captureAccessMessage = AXIsProcessTrustedWithOptions(options)
            ? "Selection capture is enabled." : "Allow Skippy in System Settings → Privacy & Security → Accessibility."
        }
      }.font(.caption)
      if let captureAccessMessage { Text(captureAccessMessage).font(.caption).foregroundStyle(.secondary) }
    }
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
        "A valid signed licence is required before Skippy's shelf, clipboard and file tools become available."
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
          Text("Skippy 1.0.0").font(.system(size: 11)).foregroundStyle(Ink.secondary)
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

private struct ScoutPreview: View {
  var body: some View {
    GeometryReader { geometry in
      let w = geometry.size.width, h = geometry.size.height
      ZStack {
        RoundedRectangle(cornerRadius: w * 0.23).fill(Ink.text)
          .frame(width: w * 0.9, height: h * 0.68).offset(y: h * 0.09)
        Capsule().fill(Ink.text).frame(width: w * 0.14, height: h * 0.30)
          .rotationEffect(.degrees(34)).offset(x: w * 0.37, y: -h * 0.35)
        HStack(spacing: w * 0.16) {
          Capsule().fill(.white)
          Capsule().fill(.white)
        }.frame(width: w * 0.48, height: h * 0.30).offset(y: h * 0.09)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }.accessibilityHidden(true)
  }
}

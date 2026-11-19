import AppKit
import ParcelCore
import SwiftUI

struct WorkbenchView: View {
  @EnvironmentObject private var store: ParcelStore
  @State private var deleteConfirmation = false
  @State private var deleteCandidate: UUID?
  @State private var sidebarCollapsed = false
  @State private var inspectorHidden = false
  @State private var showCompactSidebar = false
  @State private var showCompactInspector = false
  @StateObject private var skins = SkinStore.shared
  @ObservedObject private var shortcuts = GlobalShortcutManager.shared
  @FocusState private var searchFocused: Bool
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  var body: some View {
    GeometryReader { geo in
      let width = geo.size.width
      HStack(spacing: 0) {
        if !sidebarCollapsed && width >= 850 {
          sidebar.frame(width: 196)
          Rectangle().fill(Ink.line.opacity(0.65)).frame(width: 1)
        }
        VStack(spacing: 0) {
          header
          searchField.padding(.horizontal, 28).padding(.bottom, 12)
          if width < 850 {
            HStack {
              Button("Your parcels", systemImage: "sidebar.left") { showCompactSidebar = true }
              Spacer()
            }.font(.system(size: 11)).padding(.horizontal, 28).padding(.bottom, 10)
          }
          QuickActionsBar().environmentObject(store)
          ScrollView {
            VStack(spacing: 20) {
              ParcelHero(compact: geo.size.height < 650)
              ItemListView()
            }.padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 20)
          }.clipped()
          footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Ink.paper.opacity(reduceTransparency ? 1 : 0.84))
        if !inspectorHidden && width >= 1150 {
          Rectangle().fill(Ink.line.opacity(0.65)).frame(width: 1)
          inspector.frame(width: 250)
        }
      }
    }.background {
      if reduceTransparency { Ink.paper }
      else { CourierGlass().allowsHitTesting(false) }
    }.foregroundStyle(Ink.text)
      .preferredColorScheme(skins.skin == .night ? .dark : .light)
      .onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in store.refreshLicense() }
      .onReceive(NotificationCenter.default.publisher(for: .parcelFocusSearch)) { _ in
        searchFocused = true
      }
      .sheet(isPresented: $store.showPrepare) { PrepareSheet().environmentObject(store) }
      .sheet(isPresented: $store.showVideoPrepare) {
        MediaPreparationView(close: { store.showVideoPrepare = false }).environmentObject(store).frame(width: 360, height: 440)
      }
      .sheet(isPresented: $store.showTransform) {
        MediaPreparationView(close: { store.showTransform = false }).environmentObject(store).frame(width: 420, height: 560)
      }
      .sheet(isPresented: $store.showRenameBox) {
        RenameSheet(
          title: "Give your parcel a name", initial: store.current?.name ?? "",
          caption: "A name makes it easier to find and send again.", save: store.renameBox)
      }
      .sheet(isPresented: $store.showWelcome) { WelcomeView().environmentObject(store) }
      .sheet(isPresented: $store.showBin) { BinView().environmentObject(store) }
      .alert(
        "Something needs a little care",
        isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
      ) {
        if store.needsLibraryRecovery {
          Button("Back up and start fresh") { store.resetLibraryAfterBackup() }
        }
        Button("OK", role: .cancel) { store.error = nil }
      } message: {
        Text(store.error ?? "")
      }
      .confirmationDialog(
        "Move this parcel to the Bin?", isPresented: $deleteConfirmation,
        titleVisibility: .visible
      ) {
        Button("Move to Bin", role: .destructive) {
          if let deleteCandidate { store.moveToBin(deleteCandidate) }
        }
      } message: {
        Text("You can restore it for 30 days. Original files and saved exports stay where they are.")
      }
  }
  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      BrandMark().padding(.top, 38).padding(.horizontal, 25).padding(.bottom, 7)
      Text("A little care for your files.").font(.system(size: 10)).foregroundStyle(Ink.secondary)
        .padding(.horizontal, 25).padding(.bottom, 32)
      HStack {
        Text("YOUR PARCELS").font(.system(size: 9, weight: .semibold)).tracking(1.8)
        Spacer()
        Button {
          store.newBox()
        } label: {
          Image(systemName: "plus").font(.system(size: 13))
        }.buttonStyle(.plain).disabled(store.busy)
      }.foregroundStyle(Ink.secondary).padding(.horizontal, 25).padding(.bottom, 10)
      ScrollView {
        VStack(spacing: 5) {
          ForEach(store.filteredBoxes) { box in
            HStack(spacing: 0) {
              Button {
                store.selectBox(box.id)
                showCompactSidebar = false
              } label: {
                HStack(spacing: 9) {
                  Image(systemName: "bag").font(.system(size: 15, weight: .light))
                  VStack(alignment: .leading, spacing: 4) {
                    Text(box.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text("\(box.items.count) piece\(box.items.count == 1 ? "" : "s")")
                      .font(.system(size: 10)).foregroundStyle(Ink.secondary)
                  }
                  Spacer(minLength: 0)
                }.padding(.leading, 13).padding(.vertical, 12).contentShape(Rectangle())
              }
              Button { store.toggleParcelPin(box.id) } label: {
                Image(systemName: box.isShelfPinned ? "pin.fill" : "pin")
                  .font(.system(size: 11)).frame(width: 30, height: 36)
              }.help(box.isShelfPinned ? "Unpin parcel" : "Pin parcel first")
                .accessibilityLabel("\(box.isShelfPinned ? "Unpin" : "Pin") \(box.name)")
              Button { deleteCandidate = box.id; deleteConfirmation = true } label: {
                Image(systemName: "trash").font(.system(size: 11)).frame(width: 24, height: 36)
              }.help("Move parcel to Bin").accessibilityLabel("Move \(box.name) to Bin")
            }.buttonStyle(.plain).disabled(store.busy).foregroundStyle(Ink.green)
              .background(store.selectedBox == box.id ? Ink.paleGreen : Color.clear,
                          in: RoundedRectangle(cornerRadius: 11))
          }
          if store.isSearching && store.filteredBoxes.isEmpty {
            Text("No parcels match your search.").font(.system(size: 11))
              .foregroundStyle(Ink.secondary).padding(.top, 12)
          }
        }.padding(.horizontal, 12)
      }
      Spacer(minLength: 16)
      VStack(alignment: .leading, spacing: 14) {
        Button { store.showBin = true } label: {
          Label("Bin (\(store.trashedBoxes.count))", systemImage: "trash")
        }.buttonStyle(.plain)
        Button { AppController.shared.toggleDropPopup() } label: {
          Label("Meet your courier", systemImage: "bag")
        }.buttonStyle(.plain)
        Text("\(shortcuts.shortcut.displayName) · from anywhere").font(.system(size: 10))
          .foregroundStyle(Ink.secondary)
        Divider().overlay(Ink.line)
        Button { AppController.shared.openPreferences() } label: {
          Label("Preferences", systemImage: "slider.horizontal.3")
        }.buttonStyle(.plain)
        Text(store.license.label).font(.system(size: 10)).foregroundStyle(Ink.secondary)
      }.font(.system(size: 11)).foregroundStyle(Ink.green).padding(25)
    }.frame(maxHeight: .infinity).background(Ink.cream.opacity(reduceTransparency ? 1 : 0.7))
  }
  private var searchField: some View {
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(
          Ink.secondary)
        TextField("", text: $store.searchText)
          .textFieldStyle(.plain).font(.system(size: 12))
          .overlay(alignment: .leading) {
            if store.searchText.isEmpty {
              Text("Search parcels or ask for files").font(.system(size: 12)).foregroundStyle(Ink.secondary)
                .allowsHitTesting(false).accessibilityHidden(true)
            }
          }
          .focused($searchFocused)
          .accessibilityLabel("Search parcels and files")
          .onExitCommand { searchFocused = false }
        if store.isSearching {
          Button {
            store.clearFileSearch()
          } label: {
            Image(systemName: "xmark.circle.fill").font(.system(size: 11))
          }.buttonStyle(.plain).foregroundStyle(Ink.secondary)
        }
        FileFilterMenu()
      }.padding(.horizontal, 11).padding(.vertical, 7)
        .background(Ink.canvas, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Ink.line.opacity(0.7), lineWidth: 1))
  }
  private var header: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 4) {
        Text("THE SHELF").font(.system(size: 9, weight: .semibold)).tracking(2)
          .foregroundStyle(Ink.secondary)
        Button {
          store.showRenameBox = true
        } label: {
          HStack(spacing: 8) {
            Text(store.current?.name ?? "My parcel").font(.custom(Ink.serif, size: 27)).tracking(
              -0.6).lineLimit(1)
            Image(systemName: "pencil").font(.system(size: 11)).foregroundStyle(Ink.secondary)
          }
        }.buttonStyle(.plain).disabled(store.busy)
      }
      Spacer()
      if let box = store.current {
        Button { store.nameCurrentFromContents() } label: {
          Image(systemName: "sparkles")
        }.buttonStyle(.plain).foregroundStyle(Ink.moss).disabled(store.busy || box.items.isEmpty)
          .help("Suggest a private on-device name from file metadata")
          .accessibilityLabel("Name current parcel from its contents")
        Button { store.toggleParcelPin(box.id) } label: {
          Image(systemName: box.isShelfPinned ? "pin.fill" : "pin")
        }.buttonStyle(.plain).foregroundStyle(Ink.green).disabled(store.busy)
          .help(box.isShelfPinned ? "Unpin parcel" : "Pin parcel first")
          .accessibilityLabel("\(box.isShelfPinned ? "Unpin" : "Pin") current parcel")
        Button { deleteCandidate = box.id; deleteConfirmation = true } label: {
          Image(systemName: "trash")
        }.buttonStyle(.plain).foregroundStyle(Ink.secondary).disabled(store.busy)
          .help("Move parcel to Bin").accessibilityLabel("Move current parcel to Bin")
      }
      Button {
        if (NSApp.keyWindow?.frame.width ?? 1160) < 850 { showCompactSidebar = true }
        else { sidebarCollapsed.toggle() }
      } label: {
        Image(systemName: "sidebar.left")
      }.buttonStyle(.plain).foregroundStyle(Ink.secondary)
        .help(sidebarCollapsed ? "Show sidebar" : "Hide sidebar")
        .accessibilityLabel(sidebarCollapsed ? "Show sidebar" : "Hide sidebar")
        .popover(isPresented: $showCompactSidebar) { sidebar.frame(width: 240, height: 460) }
      Button {
        if (NSApp.keyWindow?.frame.width ?? 1160) < 1150 { showCompactInspector = true }
        else { inspectorHidden.toggle() }
      } label: {
        Image(systemName: "sidebar.right")
      }.buttonStyle(.plain).foregroundStyle(Ink.secondary)
        .help(inspectorHidden ? "Show inspector" : "Hide inspector")
        .accessibilityLabel(inspectorHidden ? "Show inspector" : "Hide inspector")
        .popover(isPresented: $showCompactInspector) { inspector.frame(width: 290, height: 460) }
      Button {
        store.addFilesPanel()
      } label: {
        Label("Add files", systemImage: "plus")
      }.buttonStyle(MossButtonStyle(secondary: true)).disabled(store.busy)
    }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
  }
  private var footer: some View {
    HStack(spacing: 10) {
      Image(systemName: "checkmark.shield").font(.system(size: 12)).foregroundStyle(Ink.moss)
      Text(store.notice ?? "Your originals always stay safe.").font(.system(size: 11))
        .foregroundStyle(Ink.secondary).lineLimit(2)
        .animation(Motion.snappyTap, value: store.notice)
      Spacer()
      Button("Bin (\(store.trashedBoxes.count))", systemImage: "trash") { store.showBin = true }
        .font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(Ink.secondary)
      if store.notice != nil {
        Button {
          store.notice = nil
        } label: {
          Image(systemName: "xmark").font(.system(size: 9))
        }.buttonStyle(.plain).foregroundStyle(Ink.secondary)
      }
    }.padding(.horizontal, 28).padding(.vertical, 15)
      .background(Ink.cream.opacity(reduceTransparency ? 1 : 0.96))
  }
  private var inspector: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 23) {
        HStack {
          Text("A LITTLE FINISHING").font(.system(size: 9, weight: .semibold)).tracking(1.5)
          Spacer()
          Image(systemName: "paperclip").font(.system(size: 12)).foregroundStyle(Ink.moss)
        }.foregroundStyle(Ink.secondary)
        // Preparing only makes sense when images are involved.
        if !store.imageItems.isEmpty || store.items.contains(where: { $0.preparedPath != nil }) {
          VStack(alignment: .leading, spacing: 12) {
            Text("Make it ready.").font(.custom(Ink.serif, size: 22)).foregroundStyle(Ink.green)
            Text("Resize, change format or lighten your images. We'll make copies.").font(
              .system(size: 11)
            ).foregroundStyle(Ink.secondary).lineSpacing(3)
            if !store.imageItems.isEmpty {
              Button {
                store.showPrepare = true
              } label: {
                Label(
                  "Prepare \(store.imageItems.count) image\(store.imageItems.count == 1 ? "" : "s")",
                  systemImage: "wand.and.stars")
              }.buttonStyle(MossButtonStyle(secondary: true)).disabled(
                store.busy || !store.canExport)
            }
            if store.items.contains(where: { $0.preparedPath != nil }) {
              Button("Use originals again") { store.restoreOriginals() }.buttonStyle(
                QuietButtonStyle()
              ).disabled(store.busy)
            }
          }
          Divider().overlay(Ink.line)
        }
        VStack(alignment: .leading, spacing: 12) {
          Text("Pack as ZIP").font(.system(size: 12, weight: .semibold)).foregroundStyle(
            Ink.green)
          Text("Only when you need a package. The shelf itself is the product.")
            .font(.system(size: 10)).foregroundStyle(Ink.secondary).lineSpacing(3)
          VStack(alignment: .leading, spacing: 7) {
            Text("Format").font(.system(size: 11)).foregroundStyle(Ink.secondary)
            Picker(selection: $store.packaging.format) {
              ForEach(PackFormat.availableCases, id: \.self) { f in Text(f.label).tag(f) }
            } label: {}.labelsHidden().pickerStyle(.segmented)
          }
          if store.packaging.format == .sevenZip
            && ExternalArchiver.toolPath(for: .sevenZip) == nil
          {
            VStack(alignment: .leading, spacing: 8) {
              Text("7-Zip isn't installed on this Mac.").font(.system(size: 10))
                .foregroundStyle(Ink.secondary).lineSpacing(3)
              if store.installingTool == .sevenZip {
                HStack(spacing: 8) {
                  ProgressView().scaleEffect(0.7)
                  Text("Installing 7-Zip…").font(.system(size: 11))
                    .foregroundStyle(Ink.secondary)
                }
              } else {
                Button("Install 7-Zip") {
                  store.installArchiverTool(.sevenZip)
                }.buttonStyle(MossButtonStyle(secondary: true))
              }
            }.padding(.vertical, 2)
          }
          VStack(alignment: .leading, spacing: 7) {
            Text("Compression").font(.system(size: 11)).foregroundStyle(Ink.secondary)
            Picker(selection: $store.packaging.strength) {
              ForEach(PackStrength.allCases, id: \.self) { s in Text(s.label).tag(s) }
            } label: {}.labelsHidden().pickerStyle(.segmented)
          }
          Text(store.packaging.strength.hint).font(.system(size: 10)).foregroundStyle(
            Ink.secondary)
          Toggle("Clean Mac ZIP clutter", isOn: $store.packaging.cleanMacMetadata).font(
            .system(size: 11))
          Toggle("Include contents list", isOn: $store.packaging.includeManifest).font(
            .system(size: 11))
          Toggle("Date on package name", isOn: $store.packaging.appendDate).font(.system(size: 11))
          Toggle("Save packed parcels to Desktop", isOn: $store.packaging.saveToDesktop).font(
            .system(size: 11))
          Text("Duplicate names get a gentle number. Your originals aren't renamed.").font(
            .system(size: 10)
          ).foregroundStyle(Ink.secondary).lineSpacing(3)
        }.toggleStyle(.checkbox).disabled(store.busy)
          .onChange(of: store.packaging) {
            _, _ in
            if !store.busy { store.invalidateArchive() }
            store.savePackaging()
          }
        VStack(alignment: .leading, spacing: 8) {
          Text("A note for the recipient").font(.system(size: 11, weight: .medium))
          TextEditor(text: Binding(get: { store.current?.note ?? "" }, set: store.updateNote)).font(
            .system(size: 11)
          ).scrollContentBackground(.hidden).frame(height: 80).padding(8).background(
            Ink.canvas, in: RoundedRectangle(cornerRadius: 8)
          ).overlay(RoundedRectangle(cornerRadius: 8).stroke(Ink.line, lineWidth: 1)).disabled(
            store.busy)
        }
        Button {
          store.copyManifest()
        } label: {
          Label("Copy contents list", systemImage: "doc.on.doc")
        }.buttonStyle(QuietButtonStyle()).disabled(store.items.isEmpty)
        Divider().overlay(Ink.line)
        VStack(alignment: .leading, spacing: 12) {
          Text("Send it on its way").font(.system(size: 12, weight: .semibold)).foregroundStyle(
            Ink.green)
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 52))], alignment: .leading, spacing: 8) {
            ShareButton(items: store.shareItems(), enabled: !store.busy && store.canExport).frame(
              height: 30)
            Button {
              store.airDrop()
            } label: {
              Image(systemName: "airplayaudio").help("AirDrop the current parcel or selected files")
            }.buttonStyle(QuietButtonStyle()).disabled(
              store.busy || store.items.isEmpty || !store.canExport)
            Button {
              store.shareViaWhatsApp()
            } label: {
              Image(systemName: "message").help("Send the packed parcel via WhatsApp")
            }.buttonStyle(QuietButtonStyle()).disabled(store.busy || !store.canExport)
            Button {
              store.copyArchiveToClipboard()
            } label: {
              Image(systemName: "doc.on.doc").help("Copy the packed parcel to the clipboard")
            }.buttonStyle(QuietButtonStyle()).disabled(
              !store.ready || store.busy || !store.canExport)
            Button {
              store.copyArchiveLink()
            } label: {
              Image(systemName: "link").help("Copy a local file link to the packed parcel (this Mac only)")
            }.buttonStyle(QuietButtonStyle()).disabled(
              !store.ready || store.busy || !store.canExport)
          }
          if store.ready {
            Button {
              store.saveArchive()
            } label: {
              Label("Save parcel", systemImage: "arrow.down.to.line")
            }.buttonStyle(QuietButtonStyle()).help("Save to your default location")
            Button {
              store.revealArchive()
            } label: {
              Label("Show in Finder", systemImage: "folder")
            }.buttonStyle(QuietButtonStyle())
          }
        }
        Spacer(minLength: 12)
        Button("Move parcel to Bin…") {
          deleteCandidate = store.selectedBox
          deleteConfirmation = true
        }.buttonStyle(QuietButtonStyle())
          .disabled(store.busy)
      }.padding(.horizontal, 25).padding(.top, 43).padding(.bottom, 20)
    }.background(Ink.cream.opacity(0.32))
  }
}

struct ParcelHero: View {
  @EnvironmentObject private var store: ParcelStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false
  var compact = false
  private var packed: Bool { store.phase == .packing || store.phase == .ready }
  private var outgoing: [URL] {
    guard !store.busy, store.canExport else { return [] }
    if store.ready, let url = store.archiveURL { return [url] }
    return store.workingItems.map(\.effectiveURL).filter {
      FileManager.default.fileExists(atPath: $0.path)
    }
  }
  var body: some View {
    let destinationBox = store.selectedBox
    VStack(spacing: 0) {
      ZStack {
        GardenBackdrop()
        CourierSatchel(sealed: packed, count: store.items.count,
                       awake: hovering, celebration: store.bounce)
        .frame(height: compact ? 104 : 180)
        .scaleEffect(hovering ? 1.04 : 1)
        .animation(
          reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: hovering)
        FileDropSurface(
          enabled: !store.busy, outgoing: outgoing, tap: { if store.ready { store.unseal() } },
          receive: { store.ingest($0, into: destinationBox) },
          receiveText: { store.ingestText($0, into: destinationBox) },
          receiving: { if $0 { store.beginReceiving() } else { store.endReceiving() } },
          hover: { hovering = $0 }, failure: { store.error = $0 })
      }.frame(height: compact ? 104 : 180)
        .background(
          hovering ? Ink.paleGreen.opacity(0.35) : Color.clear,
          in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 20).stroke(
            hovering ? Ink.moss.opacity(0.45) : Color.clear,
            style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
      VStack(spacing: 7) {
        Text(title).font(.custom(Ink.serif, size: compact ? 24 : 27)).tracking(-0.5)
          .foregroundStyle(Ink.green)
        Text(subtitle).font(.system(size: 12)).foregroundStyle(Ink.secondary)
          .multilineTextAlignment(.center)
      }.padding(.top, 2).padding(.horizontal, 20)
      .animation(Motion.snappyTap, value: store.phase)
      if store.busy {
        VStack(spacing: 9) {
          ProgressView(value: store.progress).tint(Ink.moss)
          HStack {
            Text(store.progressLabel).lineLimit(1)
            Spacer()
            Button("Cancel") { store.cancel() }.buttonStyle(.plain).foregroundStyle(Ink.green)
          }
        }.font(.system(size: 10)).padding(.horizontal, 36).padding(.top, 18).padding(.bottom, 15)
      } else {
        HStack(spacing: 10) {
          if store.ready {
            Button {
              store.unseal()
            } label: {
              Label("Open satchel", systemImage: "bag")
            }.buttonStyle(MossButtonStyle(secondary: true))
            Button {
              store.saveArchive()
            } label: {
              Label("Save parcel", systemImage: "arrow.down.to.line")
            }.buttonStyle(MossButtonStyle())
          } else {
            Button {
              store.paste()
            } label: {
              Label("Paste", systemImage: "doc.on.clipboard")
            }.buttonStyle(MossButtonStyle(secondary: true))
            Button {
              store.seal()
            } label: {
              Label("Pack \(store.packaging.format.label)", systemImage: "folder.fill")
            }.buttonStyle(MossButtonStyle()).disabled(store.items.isEmpty || !store.canExport)
          }
        }.padding(.top, compact ? 10 : 19).padding(.bottom, compact ? 8 : 14)
      }
    }
  }
  private var title: String {
    if hovering { return "A little room for your files." }
    switch store.phase {
    case .packing: return "Packing your files…"
    case .preparing: return "A little finishing touch…"
    case .ready: return "Packed. Ready to go."
    case .receiving: return "Receiving your pieces…"
    case .open:
      return store.items.isEmpty ? "Drop a few files." : "Your files, together."
    }
  }
  private var subtitle: String {
    if store.ready { return "Grab the satchel to pick up your packed file. Click it to open again." }
    if store.busy { return "Your originals stay exactly where they are." }
    if store.items.isEmpty {
      return "Put files down here. Go where you’re going. Pick them up again."
    }
    return
      "\(store.items.count) piece\(store.items.count == 1 ? "" : "s") · \(store.items.contains(where:{$0.isDirectory}) ? "files & folders" : byteString(store.current?.totalBytes ?? 0)) · grab the satchel to pick up your files"
  }
}

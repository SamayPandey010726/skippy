import AppKit
import ParcelCore
import SwiftUI

struct WorkbenchView: View {
  @EnvironmentObject private var store: ParcelStore
  @Environment(\.openWindow) private var openWindow
  @State private var deleteConfirmation = false
  @State private var sidebarCollapsed = false
  @State private var inspectorHidden = false
  var body: some View {
    GeometryReader { geo in
      let width = geo.size.width
      HStack(spacing: 0) {
        if !sidebarCollapsed {
          sidebar.frame(width: 196)
          Rectangle().fill(Ink.line.opacity(0.65)).frame(width: 1)
        }
        VStack(spacing: 0) {
          header
          QuickActionsBar().environmentObject(store)
          ScrollView {
            VStack(spacing: 20) {
              ParcelHero()
              ItemListView()
            }.padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 20)
          }
          footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Ink.paper)
        if !inspectorHidden {
          Rectangle().fill(Ink.line.opacity(0.65)).frame(width: 1)
          inspector.frame(width: 250)
        }
      }
      .onChange(of: width) { _, newWidth in
        // Adaptive columns: as the window narrows, hide the inspector
        // first, then collapse the sidebar — content never gets crushed.
        if newWidth < 1150 { inspectorHidden = true }
        if newWidth < 850 { sidebarCollapsed = true }
        if newWidth >= 1150 { inspectorHidden = false }
        if newWidth >= 850 { sidebarCollapsed = false }
      }
    }.background(Ink.paper).foregroundStyle(Ink.text).preferredColorScheme(.light)
      .onAppear { AppController.shared.showWorkbench = { openWindow(id: "workbench") } }
      .onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in store.refreshLicense() }
      .sheet(isPresented: $store.showPrepare) { PrepareSheet().environmentObject(store) }
      .sheet(isPresented: $store.showRenameBox) {
        RenameSheet(
          title: "Give your parcel a name", initial: store.current?.name ?? "",
          caption: "A name makes it easier to find and send again.", save: store.renameBox)
      }
      .sheet(isPresented: $store.showWelcome) { WelcomeView().environmentObject(store) }
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
        "Remove this parcel from your library?", isPresented: $deleteConfirmation,
        titleVisibility: .visible
      ) {
        Button("Remove parcel", role: .destructive) { store.deleteCurrentBox() }
      } message: {
        Text("Your original files and saved exports will stay where they are.")
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
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(
          Ink.secondary)
        TextField("Search parcels and files", text: $store.searchText)
          .textFieldStyle(.plain).font(.system(size: 12))
        if store.isSearching {
          Button {
            store.searchText = ""
          } label: {
            Image(systemName: "xmark.circle.fill").font(.system(size: 11))
          }.buttonStyle(.plain).foregroundStyle(Ink.secondary)
        }
      }.padding(.horizontal, 11).padding(.vertical, 7)
        .background(Ink.canvas, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Ink.line.opacity(0.7), lineWidth: 1))
        .padding(.horizontal, 14).padding(.bottom, 10)
      ScrollView {
        VStack(spacing: 5) {
          ForEach(store.filteredBoxes) { box in
            Button {
              store.selectBox(box.id)
            } label: {
              HStack(spacing: 11) {
                Image(systemName: "folder").font(.system(size: 15, weight: .light))
                VStack(alignment: .leading, spacing: 4) {
                  Text(box.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                  Text("\(box.items.count) pieces").font(.system(size: 10)).foregroundStyle(
                    Ink.secondary)
                }
                Spacer()
              }
              .foregroundStyle(Ink.green).padding(.horizontal, 13).padding(.vertical, 12)
              .background(
                store.selectedBox == box.id ? Ink.paleGreen : Color.clear,
                in: RoundedRectangle(cornerRadius: 11))
              .animation(.easeInOut(duration: 0.2), value: store.selectedBox)
            }.buttonStyle(.plain).disabled(store.busy)
          }
          if store.isSearching && store.filteredBoxes.isEmpty {
            Text("No parcels match “\(store.searchText)”.").font(.system(size: 11))
              .foregroundStyle(Ink.secondary).padding(.top, 12)
          }
        }.padding(.horizontal, 12)
      }
      Spacer(minLength: 16)
      VStack(alignment: .leading, spacing: 14) {
        Button {
          AppController.shared.toggleDropPopup()
        } label: {
          Label("Drop popup", systemImage: "rectangle.on.rectangle")
        }.buttonStyle(.plain)
        HStack {
          Text("⌃ ⌥ P").font(.system(size: 10, design: .monospaced))
          Text("from anywhere").font(.system(size: 10))
        }.foregroundStyle(Ink.secondary)
        Divider().overlay(Ink.line)
        SettingsLink { Label("Preferences", systemImage: "slider.horizontal.3") }.buttonStyle(
          .plain)
        Text(store.license.label).font(.system(size: 10)).foregroundStyle(Ink.secondary)
      }.font(.system(size: 11)).foregroundStyle(Ink.green).padding(25)
    }.frame(maxHeight: .infinity).background(Ink.cream.opacity(0.65))
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
              -0.6)
            Image(systemName: "pencil").font(.system(size: 11)).foregroundStyle(Ink.secondary)
          }
        }.buttonStyle(.plain).disabled(store.busy)
      }
      Spacer()
      Button {
        sidebarCollapsed.toggle()
      } label: {
        Image(systemName: "sidebar.left")
      }.buttonStyle(.plain).foregroundStyle(Ink.secondary)
        .help(sidebarCollapsed ? "Show sidebar" : "Hide sidebar")
        .accessibilityLabel(sidebarCollapsed ? "Show sidebar" : "Hide sidebar")
      Button {
        inspectorHidden.toggle()
      } label: {
        Image(systemName: "sidebar.right")
      }.buttonStyle(.plain).foregroundStyle(Ink.secondary)
        .help(inspectorHidden ? "Show inspector" : "Hide inspector")
        .accessibilityLabel(inspectorHidden ? "Show inspector" : "Hide inspector")
      Button {
        store.addFilesPanel()
      } label: {
        Label("Add files", systemImage: "plus")
      }.buttonStyle(MossButtonStyle(secondary: true)).disabled(store.busy)
    }.padding(.horizontal, 28).padding(.top, 36).padding(.bottom, 15)
  }
  private var footer: some View {
    HStack(spacing: 10) {
      Image(systemName: "checkmark.shield").font(.system(size: 12)).foregroundStyle(Ink.moss)
      Text(store.notice ?? "Your originals always stay safe.").font(.system(size: 11))
        .foregroundStyle(Ink.secondary).lineLimit(2)
        .animation(.easeInOut(duration: 0.25), value: store.notice)
      Spacer()
      if store.notice != nil {
        Button {
          store.notice = nil
        } label: {
          Image(systemName: "xmark").font(.system(size: 9))
        }.buttonStyle(.plain).foregroundStyle(Ink.secondary)
      }
    }.padding(.horizontal, 28).padding(.vertical, 15).background(Ink.cream.opacity(0.4))
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
          HStack {
            Text("Format").font(.system(size: 11)).foregroundStyle(Ink.secondary)
            Spacer()
            Picker(selection: $store.packaging.format) {
              ForEach(PackFormat.availableCases, id: \.self) { f in Text(f.label).tag(f) }
            } label: {}.labelsHidden().pickerStyle(.segmented).frame(width: 168)
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
          HStack {
            Text("Compression").font(.system(size: 11)).foregroundStyle(Ink.secondary)
            Spacer()
            Picker(selection: $store.packaging.strength) {
              ForEach(PackStrength.allCases, id: \.self) { s in Text(s.label).tag(s) }
            } label: {}.labelsHidden().pickerStyle(.segmented).frame(width: 168)
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
          HStack {
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
              Image(systemName: "link").help("Copy a shareable link to the packed parcel")
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
        Button("Remove parcel…") { deleteConfirmation = true }.buttonStyle(QuietButtonStyle())
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
        ParcelIllustration(
          sealed: packed, count: store.items.count, bounce: store.bounce,
          receiving: store.phase == .receiving, stamped: store.ready
        )
        .frame(height: compact ? 236 : 270)
        .scaleEffect(hovering ? 1.04 : 1)
        .animation(
          reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: hovering)
        FileDropSurface(
          enabled: !store.busy, outgoing: outgoing, tap: { if store.ready { store.unseal() } },
          receive: { store.ingest($0, into: destinationBox) },
          receiveText: { store.ingestText($0, into: destinationBox) },
          receiving: { if $0 { store.beginReceiving() } else { store.endReceiving() } },
          hover: { hovering = $0 }, failure: { store.error = $0 })
      }.frame(height: compact ? 236 : 270)
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
      .animation(.easeInOut(duration: 0.25), value: store.phase)
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
              Label("Open folder", systemImage: "folder")
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
        }.padding(.top, 19).padding(.bottom, 14)
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
    if store.ready { return "Grab the parcel to drag a real ZIP. Click it to open again." }
    if store.busy { return "Your originals stay exactly where they are." }
    if store.items.isEmpty {
      return "Drop files here. They stay where they are — Parcel only keeps references, never copies."
    }
    return
      "\(store.items.count) pieces · \(store.items.contains(where:{$0.isDirectory}) ? "files & folders" : byteString(store.current?.totalBytes ?? 0)) · grab the folder to drag loose files"
  }
}

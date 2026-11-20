import AppKit
import Carbon
import Combine
import ParcelCore
import SwiftUI

@MainActor final class AppController: NSObject, NSWindowDelegate {
  static let shared = AppController()
  private weak var store: ParcelStore?
  private var workbench: NSWindow?
  private var preferencesWindow: NSWindow?
  private var skinObserver: AnyCancellable?
  private var licenseObserver: AnyCancellable?
  private var operationalServicesInstalled = false
  var isWorkbenchVisible: Bool { workbench?.isVisible == true }
  func restoreAccessoryPolicyIfPossible() {
    if workbench?.isVisible != true && preferencesWindow?.isVisible != true {
      NSApp.setActivationPolicy(SkippyQuiver.shared.surface == .dock ? .regular : .accessory)
    }
  }
  func install(store: ParcelStore) {
    guard self.store == nil else { return }
    self.store = store
    skinObserver = SkinStore.shared.$skin.sink { [weak self] skin in
      let appearance = NSAppearance(named: skin == .night ? .darkAqua : .aqua)
      self?.workbench?.appearance = appearance
      self?.preferencesWindow?.appearance = appearance
    }
    licenseObserver = store.$license.removeDuplicates().sink { [weak self, weak store] status in
      guard let self, let store else { return }
      if status.canUseApp { self.installOperationalServices(store: store) }
      else { self.showActivation() }
    }
  }
  private func installOperationalServices(store: ParcelStore) {
    guard !operationalServicesInstalled else { restoreAccessoryPolicyIfPossible(); return }
    operationalServicesInstalled = true
    WatchedFolders.shared.start(store: store)
    SkippyQuiver.shared.install()
    DropPopupController.shared.install(store: store)
    ParcelFileService.shared.install(store: store)
    SpotlightIndexer.shared.install(store: store)
    ClipboardHistoryStore.shared.start()
    GlobalShortcutManager.shared.install { AppController.shared.handleGlobalShortcut() }
    store.checkCacheOnStartup()
  }
  func showActivation() {
    guard let store, !store.license.canUseApp else { return }
    presentSettings(initialTab: 3)
  }
  /// The drop popup appears while files are dragged; the configurable global shortcut summons it by hand.
  func toggleDropPopup() {
    guard store?.license.canUseApp == true else { showActivation(); return }
    DropPopupController.shared.togglePopup()
  }
  func handleGlobalShortcut() {
    guard store?.license.canUseApp == true else { showActivation(); return }
    let selected = FinderSelection.urls()
    if !selected.isEmpty {
      let shelf = DropPopupController.shared
      shelf.showModule(.parcel)
      shelf.focusForKeyboard()
      shelf.beginPrimaryDrop()?.receive(selected)
      return
    }
    guard SelectionCapture.capture({ captured in
      guard captured else {
        DropPopupController.shared.toggleDashboard()
        return
      }
      let shelf = DropPopupController.shared
      shelf.showModule(.parcel)
      shelf.focusForKeyboard()
      shelf.pasteFiles()
    }) else {
      DropPopupController.shared.toggleDashboard()
      return
    }
  }
  func showTutorial() {
    guard let store, store.license.canUseApp else { showActivation(); return }
    presentSettings(initialTab: 5)
  }
  func closeTutorial() {
    preferencesWindow?.orderOut(nil)
    restoreAccessoryPolicyIfPossible()
  }
  func openBin() {
    guard store?.license.canUseApp == true else { showActivation(); return }
    DropPopupController.shared.expand()
    DropPopupController.shared.showingBin = true
    DropPopupController.shared.fitContents()
  }
  /// Dock menu: open a parcel item directly.
  @objc nonisolated func openDockItem(_ sender: NSMenuItem) {
    if let path = sender.representedObject as? String {
      DispatchQueue.main.async {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
      }
    }
  }
  func openWorkbench() {
    guard store?.license.canUseApp == true else { showActivation(); return }
    DropPopupController.shared.showModule(.dashboard)
  }
  func openPreferences() { presentSettings(initialTab: nil) }
  private func presentSettings(initialTab: Int?) {
    guard let store else { return }
    if preferencesWindow == nil {
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 540),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      window.title = "Skippy Settings"; window.isReleasedWhenClosed = false
      window.isRestorable = false
      window.delegate = self
      window.center(); preferencesWindow = window
    }
    if !(preferencesWindow?.contentView is NSHostingView<AnyView>) || initialTab != nil {
      preferencesWindow?.contentView = NSHostingView(rootView: AnyView(UniversalInterface { PreferencesView(initialTab: initialTab ?? 0).environmentObject(store) }))
    }
    preferencesWindow?.appearance = NSAppearance(named: SkinStore.shared.skin == .night ? .darkAqua : .aqua)
    DropPopupController.shared.dismiss()
    preferencesWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  func windowWillClose(_ notification: Notification) { DispatchQueue.main.async { self.restoreAccessoryPolicyIfPossible() } }
  func fitInterfaceWindows() {
    guard let workbench else { return }
    let scale = DropPopupController.shared.interfaceScale
    let screen = workbench.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? workbench.frame
    workbench.minSize = CGSize(width: min(720 * scale, screen.width), height: min(520 * scale, screen.height))
    let size = CGSize(width: min(screen.width, max(workbench.minSize.width, workbench.frame.width)),
      height: min(screen.height, max(workbench.minSize.height, workbench.frame.height)))
    workbench.setFrame(CGRect(origin: CGPoint(x: min(max(workbench.frame.minX, screen.minX), screen.maxX - size.width),
      y: min(max(workbench.frame.minY, screen.minY), screen.maxY - size.height)), size: size), display: true)
  }
}

enum FinderSelection {
  static func hasAccess(request: Bool) -> Bool {
    let finder = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
    return AEDeterminePermissionToAutomateTarget(finder.aeDesc, typeWildCard, typeWildCard, request) == noErr
  }
  static func urls() -> [URL] {
    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder", hasAccess(request: false) else { return [] }
    let source = """
      tell application "Finder"
        set selectedPaths to ""
        repeat with selectedItem in selection
          set selectedPaths to selectedPaths & POSIX path of (selectedItem as alias) & linefeed
        end repeat
        return selectedPaths
      end tell
      """
    var error: NSDictionary?
    guard let value = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue else { return [] }
    return value.split(whereSeparator: \.isNewline).map { URL(fileURLWithPath: String($0)).standardizedFileURL }
      .filter { FileManager.default.fileExists(atPath: $0.path) }
  }
}

enum SelectionCapture {
  private struct Snapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
    init(_ board: NSPasteboard) {
      items = (board.pasteboardItems ?? []).map { item in
        Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
          item.data(forType: type).map { (type, $0) }
        })
      }
    }
    func restore(to board: NSPasteboard) {
      let restored = items.map { values -> NSPasteboardItem in
        let item = NSPasteboardItem()
        values.forEach { item.setData($1, forType: $0) }
        return item
      }
      board.clearContents()
      board.writeObjects(restored)
    }
  }
  static func capture(_ completion: @escaping @MainActor (Bool) -> Void) -> Bool {
    guard let application = NSWorkspace.shared.frontmostApplication,
      application.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
    guard AXIsProcessTrusted() else { return false }
    let board = NSPasteboard.general
    let snapshot = Snapshot(board)
    let change = board.changeCount
    let source = CGEventSource(stateID: .combinedSessionState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
    down?.flags = .maskCommand; up?.flags = .maskCommand
    down?.postToPid(application.processIdentifier); up?.postToPid(application.processIdentifier)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      let captured = board.changeCount != change
      completion(captured)
      if captured { snapshot.restore(to: board) }
    }
    return true
  }
}

@MainActor final class ParcelAppDelegate: NSObject, NSApplicationDelegate {
  private var launchTime = ProcessInfo.processInfo.systemUptime
  func applicationDidFinishLaunching(_ notification: Notification) {
    launchTime = ProcessInfo.processInfo.systemUptime
    NSApp.setActivationPolicy(.accessory)
    AppController.shared.install(store: ParcelRuntime.store)
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    guard ParcelRuntime.store.license.canUseApp else {
      AppController.shared.showActivation()
      return false
    }
    if Self.shouldSummonShelf(secondsSinceLaunch: ProcessInfo.processInfo.systemUptime - launchTime) {
      DropPopupController.shared.summon()
    }
    return false
  }
  static func shouldSummonShelf(secondsSinceLaunch: TimeInterval) -> Bool { secondsSinceLaunch >= 1 }
  static func shouldOpenWorkbench(launchFinished: Bool, isExplicitReopen: Bool) -> Bool {
    false
  }
  func applicationDidBecomeActive(_ notification: Notification) {
    if ParcelRuntime.store.license.canUseApp && DragMonitor.shared.isDragging {
      DropPopupController.shared.showIfDragging()
    }
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard ParcelRuntime.store.busy || ParcelRuntime.store.phase == .receiving else { return .terminateNow }
    let alert = NSAlert()
    alert.messageText = "A parcel is still being received or prepared."
    alert.informativeText =
      "Wait for it to finish, or cancel the operation in Skippy before quitting. Your originals are safe."
    alert.addButton(withTitle: "Keep Skippy open")
    alert.runModal()
    return .terminateCancel
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  /// Right-click the Dock icon: packed parcels fan out, anything opens directly.
  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    let store = ParcelRuntime.store
    guard store.license.canUseApp else { return nil }
    let menu = SkippyQuiver.shared.menu()
    if !store.recentParcels.isEmpty { menu.addItem(.separator()) }
    for box in store.recentParcels.prefix(6) {
      let sub = NSMenu()
      for item in box.items.prefix(15) {
        let mi = NSMenuItem(
          title: item.displayName, action: #selector(AppController.openDockItem(_:)),
          keyEquivalent: "")
        mi.target = AppController.shared
        mi.representedObject = item.effectiveURL.path
        sub.addItem(mi)
      }
      let mi = NSMenuItem(title: box.name, action: nil, keyEquivalent: "")
      mi.submenu = sub
      menu.addItem(mi)
    }
    return menu
  }
  func application(_ application: NSApplication, open urls: [URL]) {
    AppController.shared.install(store: ParcelRuntime.store)
    guard ParcelRuntime.store.license.canUseApp else { AppController.shared.showActivation(); return }
    if let url = urls.first, url.scheme == "parcel", url.host == "open",
      let id = UUID(uuidString: url.lastPathComponent),
      ParcelRuntime.store.boxes.contains(where: { $0.id == id }) {
      ParcelRuntime.store.selectBox(id)
      DropPopupController.shared.summon()
      DropPopupController.shared.openPrimaryFiles()
      return
    }
    DropPopupController.shared.summon()
    DropPopupController.shared.beginPrimaryDrop()?.receive(urls)
  }
}
@MainActor enum ParcelRuntime {
  static let store = ParcelStore()
}

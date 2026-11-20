import AppKit
import Combine
import ParcelCore
import SwiftUI

final class ShelfPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

struct CourierMoveHandle: NSViewRepresentable {
  var move: (NSEvent) -> Void
  func makeNSView(context: Context) -> HandleView { HandleView() }
  func updateNSView(_ view: HandleView, context: Context) { view.move = move }
  final class HandleView: NSView {
    var move: (NSEvent) -> Void = { _ in }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { move(event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
  }
}

private final class CourierHostingView: NSHostingView<AnyView> {
  var pointerChanged: (() -> Void)?
  var keyHandler: ((NSEvent) -> Bool)?
  private var pointerArea: NSTrackingArea?
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let pointerArea { removeTrackingArea(pointerArea) }
    let area = NSTrackingArea(rect: .zero,
      options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
      owner: self, userInfo: nil)
    addTrackingArea(area)
    pointerArea = area
  }
  override func mouseEntered(with event: NSEvent) { pointerChanged?() }
  override func mouseExited(with event: NSEvent) { pointerChanged?() }
  override func mouseMoved(with event: NSEvent) { pointerChanged?() }
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func keyDown(with event: NSEvent) {
    if keyHandler?(event) != true { super.keyDown(with: event) }
  }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    keyHandler?(event) == true || super.performKeyEquivalent(with: event)
  }
}

@MainActor final class DropPopupController: NSObject, ObservableObject {
  static let shared = DropPopupController()
  @Published private(set) var expanded = false
  @Published private(set) var showingFolder = false
  @Published private(set) var controlsVisible = false
  @Published private(set) var parkedInMenuBar = false
  @Published var showingBin = false
  @Published var mediaEditor = false
  @Published private(set) var toolsVisible = false
  @Published private(set) var activeModule: NotchModule = .dashboard
  @Published private(set) var visible = false
  @Published private(set) var reveal = 0
  @Published private(set) var destinations: [ParcelBox] = []
  @Published private(set) var focusedBox: UUID?
  @Published private(set) var message = "Put files down. Pick them up anywhere."
  @Published private(set) var failed = false
  @Published private(set) var statusVisible = false
  @Published private(set) var receiving = false
  @Published private(set) var incoming = false
  @Published private(set) var courierHovered = false
  @Published private(set) var intakeEvent = 0
  @Published private(set) var intakeCount = 0
  @Published private(set) var intakeBox: UUID?
  @Published private(set) var keyboardFocusedItem: UUID?
  let filePreview = CourierHoverPreview()
  private let sidePreview = CourierSidePreviewController()
  private let clipboard = CourierClipboardController()
  private let searchPanel = CourierSearchPanelController()
  private let optionsPanel = CourierOptionsPanelController()
  private var filePreviewObserver: AnyCancellable?
  private weak var store: ParcelStore?
  private var panel: ShelfPanel?
  private weak var host: CourierHostingView?
  private var hideWork: DispatchWorkItem?
  private var trackedMenus: Set<ObjectIdentifier> = []
  private var confirmingAction = false
  private var selectingOnScreen = false
  private var selectionEndedAt: TimeInterval = 0
  private var expandWork: DispatchWorkItem?
  private var folderWork: DispatchWorkItem?
  private var observers: [NSObjectProtocol] = []
  private var eventMonitors: [Any] = []
  private var phaseObserver: AnyCancellable?
  private var boxesObserver: AnyCancellable?
  private var previewWork: DispatchWorkItem?
  private var pendingPreview: UUID?
  private var waitForPointerExit = false
  private var awaitingSummonedPointerEntry = false
  private var generation = 0
  private var moveCompletion: Timer?
  private var movingCourierFrame: CGRect?
  private var hasReceipt = false
  private var sharingPicker: NSSharingServicePicker?
  private var idleWork: DispatchWorkItem?
  private var lastActivity = ProcessInfo.processInfo.systemUptime
  private var pointerInside = false
  private var topRight: CGPoint?
  private var moving = false
  private var pendingMoveLayout = false
  private var suspendedForQuickConvert = false
  private var restoreAfterQuickConvert = false
  private var topEdgeWork: DispatchWorkItem?
  private var clipboardHideWork: DispatchWorkItem?
  private var clipboardHoverActive = false
  private var clipboardPinnedOpen = false
  private var searchPinnedOpen = false
  private var searchHideWork: DispatchWorkItem?
  private var optionsPinnedOpen = false
  private var optionsHideWork: DispatchWorkItem?
  private var topEdgeLatched = false
  private let defaults: UserDefaults
  private let displayPositions: CourierDisplayPositions
  private let hoverDelay: TimeInterval
  private let folderHoverDelay: TimeInterval
  @Published private(set) var choosingArrow = false
  @Published private(set) var isArrowPreview = false
  var quiverAnchor: (() -> CGRect?)?
  var quiverPanelPointer: ((Bool) -> Void)?
  private var quiverPointerInside = false
  var presentationFrame: CGRect? { panel?.isVisible == true ? panel?.frame : nil }
  private var menuAnchor: CGRect?
  private var restoredAnchor: CGPoint?
  private var placementScreen: CGRect?
  private var placementPhysicalScreen: CGRect?
  var primaryBox: ParcelBox? { store?.rankedBoxes.first }
  var idleTimeout: TimeInterval {
    get {
      let value = defaults.object(forKey: "parcel.idleTimeout") as? Double ?? 30
      return value == 0 ? 0 : (value.isFinite ? min(3600, max(5, value)) : 30)
    }
    set {
      objectWillChange.send()
      defaults.set(newValue == 0 ? 0 : (newValue.isFinite ? min(3600, max(5, newValue)) : 30), forKey: "parcel.idleTimeout")
      idleWork?.cancel(); idleWork = nil; recordActivity()
    }
  }
  var dialRadius: CGFloat { max(150, courierSize.width / 2 + 52) }
  var interfaceScale: CGFloat {
    get { CourierLayout.boundedInterfaceScale(CGFloat(defaults.object(forKey: "parcel.interfaceScale") as? Double ?? 1)) }
    set {
      objectWillChange.send()
      defaults.set(Double(CourierLayout.boundedInterfaceScale(newValue)), forKey: "parcel.interfaceScale")
      clampAnchor(); fitContents(); recordActivity()
    }
  }
  var iconSize: CGFloat {
    get { CourierLayout.boundedIconSize(CGFloat(defaults.object(forKey: "parcel.courierIconSize") as? Double ?? Double(CourierLayout.defaultIconSize))) }
    set {
      objectWillChange.send()
      defaults.set(Double(CourierLayout.boundedIconSize(newValue)), forKey: "parcel.courierIconSize")
      clampAnchor()
      fitContents()
    }
  }
  var closeControlScale: CGFloat {
    get { CourierLayout.boundedControlScale(CGFloat(defaults.object(forKey: "parcel.closeControlScale") as? Double ?? 1)) }
    set { objectWillChange.send(); defaults.set(Double(CourierLayout.boundedControlScale(newValue)), forKey: "parcel.closeControlScale"); clampAnchor(); fitContents() }
  }
  var expandControlScale: CGFloat {
    get { CourierLayout.boundedControlScale(CGFloat(defaults.object(forKey: "parcel.expandControlScale") as? Double ?? 1)) }
    set { objectWillChange.send(); defaults.set(Double(CourierLayout.boundedControlScale(newValue)), forKey: "parcel.expandControlScale"); clampAnchor(); fitContents() }
  }
  var closeControlSize: CGFloat { max(32 / interfaceScale, CourierLayout.buttonSize(iconSize: iconSize, scale: closeControlScale)) }
  var expandControlSize: CGFloat { max(32 / interfaceScale, CourierLayout.buttonSize(iconSize: iconSize, scale: expandControlScale)) }
  var courierSize: CGSize { CGSize(width: max(iconSize + 16, closeControlSize + expandControlSize + 24), height: iconSize + max(closeControlSize, expandControlSize) + 8) }
  var physicalCourierSize: CGSize { CGSize(width: courierSize.width * interfaceScale, height: courierSize.height * interfaceScale) }
  var viewStyle: CourierViewStyle {
    get { CourierViewStyle(rawValue: defaults.string(forKey: "parcel.courierPresentationStyle") ?? "dial") ?? .dial }
    set { objectWillChange.send(); defaults.set(newValue.rawValue, forKey: "parcel.courierPresentationStyle"); fitContents() }
  }
  var side: CourierSide {
    get { CourierSide(rawValue: defaults.string(forKey: "parcel.courierSide") ?? "left") ?? .left }
    set { objectWillChange.send(); defaults.set(newValue.rawValue, forKey: "parcel.courierSide"); fitContents() }
  }
  var remembersPositionPerDisplay: Bool {
    get { defaults.object(forKey: "parcel.rememberPositionPerDisplay") as? Bool ?? true }
    set {
      objectWillChange.send()
      defaults.set(newValue, forKey: "parcel.rememberPositionPerDisplay")
      place(on: pointerScreen(), useSaved: true)
    }
  }
  init(store: ParcelStore? = nil, defaults: UserDefaults = .standard, hoverDelay: TimeInterval = 1,
       folderHoverDelay: TimeInterval = 0.04) {
    self.store = store
    self.defaults = defaults
    displayPositions = CourierDisplayPositions(defaults: defaults)
    self.hoverDelay = hoverDelay
    self.folderHoverDelay = folderHoverDelay
    destinations = []
    super.init()
    filePreviewObserver = filePreview.$item.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
      guard let self else { return }
      self.resizeKeepingAnchor()
      if self.filePreview.item == nil, self.visible { self.scheduleHide(after: 0.08) }
    }
    if let store { observe(store) }
  }
  private func observe(_ store: ParcelStore) {
    boxesObserver = store.$boxes.receive(on: RunLoop.main).sink { [weak self, weak store] _ in
      guard let self, let store else { return }
      let boxes = store.boxes
      if !DragMonitor.shared.isDragging && !self.receiving {
        self.destinations = []
      } else {
        self.destinations = self.destinations.compactMap { old in boxes.first { $0.id == old.id } }
      }
      if let focused = self.focusedBox, !boxes.contains(where: { $0.id == focused }) {
        self.focusedBox = nil
      }
    }
    phaseObserver = store.$phase.dropFirst().receive(on: RunLoop.main).sink { [weak self] phase in
      self?.recordActivity()
      guard let self, self.visible, self.focusedBox != nil else { return }
      if phase == .ready {
        self.message = "Packed. Ready for the next stop."
        self.failed = false
        self.statusVisible = true
        self.reveal += 1
      }
      if phase == .open || phase == .ready { self.scheduleHide(after: 1.2) }
      else { self.cancelHide() }
    }
  }
  var isVisible: Bool { panel?.isVisible == true }
  var isClipboardVisible: Bool { clipboard.panel?.isVisible == true }
  var isSearchVisible: Bool { searchPanel.panel?.isVisible == true }
  var isOptionsVisible: Bool { optionsPanel.panel?.isVisible == true }
  var contentSize: CGSize {
    arrangement.frame.size
  }
  var arrangement: CourierPlacement {
    let visibleScreen = placementScreen ?? panel?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    // The notch occupies the menu bar itself; visibleFrame starts below it.
    let screen = parkedInMenuBar ? (placementPhysicalScreen ?? panel?.screen?.frame ?? NSScreen.main?.frame ?? visibleScreen) : visibleScreen
    if expanded, let anchor = menuAnchor, quiverAnchor != nil {
      let bounds = NSScreen.screens.first { $0.frame.intersects(anchor) }?.visibleFrame ?? visibleScreen
      let size = CGSize(width: 460 * interfaceScale, height: 340 * interfaceScale)
      let frame = QuiverSurface.panel(at: anchor, within: bounds, size: size)
      return CourierPlacement(frame: frame, courier: .zero, pane: CGRect(origin: .zero, size: frame.size), side: .bottom)
    }
    if parkedInMenuBar && !expanded {
      let ambientCount = NotchWidgetStore.shared.pinned.count + NotchToolStore.shared.pinnedApps.count
      let size = CGSize(width: min(screen.width - 24, CGFloat(160 + min(3, ambientCount) * 29) * interfaceScale),
        height: 36 * interfaceScale)
      let frame = CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height,
        width: size.width, height: size.height)
      return CourierPlacement(frame: frame, courier: CGRect(origin: .zero, size: size), pane: nil, side: .bottom)
    }
    if parkedInMenuBar && expanded {
      if toolsVisible && activeModule != .parcel {
        let size = CGSize(width: min(460, max(410, screen.width * 0.24)),
          height: min(340, screen.height * 0.4))
        let frame = CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height,
          width: size.width, height: size.height)
        return CourierPlacement(frame: frame,
          courier: CGRect(x: frame.width / 2, y: frame.height, width: 1, height: 1),
          pane: CGRect(origin: .zero, size: size), side: .bottom)
      }
      let size: CGSize
      switch viewStyle {
      case .dial: size = CGSize(width: min(390, max(350, screen.width * 0.20)), height: 174)
      case .grid: size = CGSize(width: min(370, max(340, screen.width * 0.19)), height: 238)
      case .list: size = CGSize(width: min(310, max(286, screen.width * 0.16)), height: 278)
      }
      let width = size.width
      let height = min(size.height, screen.height * 0.4)
      let frame = CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height)
      let local = CGRect(origin: .zero, size: frame.size)
      return CourierPlacement(frame: frame, courier: CGRect(x: frame.width / 2, y: frame.height, width: 1, height: 1),
        pane: local, side: .bottom)
    }
    let anchor = topRight ?? topCenterAnchor(in: screen)
    let size = physicalCourierSize
    let courier = menuAnchor ?? CGRect(x: anchor.x - size.width, y: anchor.y - size.height, width: size.width, height: size.height)
    let count = store?.boxes.first(where: { $0.id == focusedBox })?.items.count ?? 0
    if expanded && toolsVisible {
      return CourierSideLayout.placement(courier: courier, screen: screen,
        pane: CGSize(width: 460 * interfaceScale, height: min(330 * interfaceScale, screen.height * 0.4)),
        side: side)
    }
    let rows = max(1, (count + 2) / 3)
    let fanSize = side.isVertical ? CGSize(width: count > 3 ? 500 : 340, height: count > 3 ? 330 : 260) : CourierSideLayout.fanSize(itemCount: count)
    let folderSize = viewStyle == .dial ? fanSize : CGSize(width: CourierSideLayout.folder.width,
      height: viewStyle == .grid ? min(390, 145 + CGFloat(rows) * 72) : CourierSideLayout.folder.height)
    if expanded && !showingFolder && !showingBin && !mediaEditor && !toolsVisible && !parkedInMenuBar {
      return CourierSideLayout.newOptionPlacement(courier: courier, screen: screen,
        size: CGSize(width: CourierSideLayout.choices.width * interfaceScale, height: CourierSideLayout.choices.height * interfaceScale))
    }
    if expanded && showingFolder && viewStyle == .dial && !showingBin && !mediaEditor {
      let center = CGPoint(x: courier.midX, y: courier.maxY - (max(closeControlSize, expandControlSize) + iconSize / 2) * interfaceScale)
      let query = store?.fileQuery
      let header: CGFloat = 48 + ((statusVisible || failed) ? 26 : 0) + ((store?.busy == true || receiving) ? 26 : 0)
        + ((query?.dateDescription != nil || query?.warning != nil) ? 14 : 0)
      if parkedInMenuBar {
        return CourierSideLayout.menuDialPlacement(courier: courier, screen: screen,
          count: count, scale: interfaceScale, headerHeight: header)
      }
      return CourierSideLayout.dialPlacement(courier: courier, iconCenter: center, screen: screen,
        side: parkedInMenuBar ? .bottom : side, radius: dialRadius * interfaceScale, scale: interfaceScale, count: count, headerHeight: header)
    }
    let desired = (showingBin || mediaEditor) ? CourierSideLayout.folder : (showingFolder ? folderSize : CourierSideLayout.choices)
    return CourierSideLayout.placement(courier: courier, screen: screen,
      pane: expanded ? CGSize(width: desired.width * interfaceScale, height: desired.height * interfaceScale) : nil,
      side: parkedInMenuBar ? .bottom : side)
  }
  var logicalArrangement: CourierPlacement {
    let physical = arrangement
    func unscale(_ rect: CGRect) -> CGRect {
      CGRect(x: rect.minX / interfaceScale, y: rect.minY / interfaceScale,
        width: rect.width / interfaceScale, height: rect.height / interfaceScale)
    }
    return CourierPlacement(frame: CGRect(origin: physical.frame.origin, size: unscale(physical.frame).size),
      courier: unscale(physical.courier), pane: physical.pane.map(unscale), side: physical.side)
  }
  func fitContents() { resizeKeepingAnchor() }
  var isEnabled: Bool {
    get { defaults.object(forKey: "parcel.dropPopupEnabled") as? Bool ?? true }
    set {
      objectWillChange.send()
      defaults.set(newValue, forKey: "parcel.dropPopupEnabled")
      if newValue, isPersistent { restoreResident() }
      else if !newValue { hideIsland() }
    }
  }
  var isPersistent: Bool {
    get { defaults.object(forKey: "parcel.persistentCourier") as? Bool ?? true }
    set {
      objectWillChange.send()
      defaults.set(newValue, forKey: "parcel.persistentCourier")
      if newValue { restoreResident() }
      else if !expanded { hideIsland() }
    }
  }
  var shiftConvertEnabled: Bool {
    get { defaults.object(forKey: "parcel.shiftConvertEnabled") as? Bool ?? true }
    set { objectWillChange.send(); defaults.set(newValue, forKey: "parcel.shiftConvertEnabled") }
  }
  var shiftConvertAppearance: QuickConvertAppearance {
    get { QuickConvertAppearance(rawValue: defaults.string(forKey: "parcel.shiftConvertAppearance") ?? "glass") ?? .glass }
    set {
      objectWillChange.send(); defaults.set(newValue.rawValue, forKey: "parcel.shiftConvertAppearance")
      DragConvertController.shared.appearance = newValue
    }
  }

  func install(store: ParcelStore) {
    guard self.store == nil else { return }
    if defaults.object(forKey: "parcel.referenceFanEnabled") == nil {
      defaults.set(CourierViewStyle.dial.rawValue, forKey: "parcel.courierPresentationStyle")
      defaults.set(true, forKey: "parcel.referenceFanEnabled")
    }
    self.store = store
    if !defaults.bool(forKey: "parcel.topCenterPlacement.v1") {
      displayPositions.reset()
      defaults.set(true, forKey: "parcel.topCenterPlacement.v1")
    }
    DragConvertController.shared.install(store: store)
    DragConvertController.shared.appearance = shiftConvertAppearance
    DragConvertController.shared.onVisibilityChanged = { [weak self] visible in
      if visible { self?.suspendForQuickConvert() }
      else { self?.resumeAfterQuickConvert() }
    }
    observe(store)
    DragMonitor.shared.onDragState = { [weak self] dragging in
      guard let self else { return }
      self.incoming = dragging && self.isEnabled
      if self.incoming { self.reveal += 1 }
      if dragging { self.showForDrag() }
      else {
        self.destinations = []
        self.scheduleHide(after: 0.6)
      }
    }
    DragMonitor.shared.onDragLocation = { [weak self] point in self?.followDisplay(point) }
    DragMonitor.shared.onTopEdgeHover = { [weak self] point in self?.topEdgeHover(at: point) }
    DragMonitor.shared.onShiftFileDrag = { urls, point in
      if let urls, DropPopupController.shared.shiftConvertEnabled {
        DragConvertController.shared.present(urls: urls, at: point)
      }
      else { DragConvertController.shared.dragEnded() }
    }
    DragMonitor.shared.shouldDetectShake = { [weak self] in self?.parkedInMenuBar == true }
    DragMonitor.shared.onMouseShake = { [weak self] in self?.summonFromMouseShake() }
    let workspace = NSWorkspace.shared.notificationCenter
    observers.append(workspace.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        if self?.visible == true { self?.panel?.orderFrontRegardless() }
      }
    })
    observers.append(NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.visible else { return }
        self.place(on: self.pointerScreen(), useSaved: false)
      }
    })
    if let monitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown],
      handler: { [weak self] event in
        let timestamp = event.timestamp
        Task { @MainActor in self?.collapseForOutsideClick(at: NSEvent.mouseLocation, timestamp: timestamp) }
      }) {
      eventMonitors.append(monitor)
    }
    if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
      // A local click belongs to Parcel (the notch, a child tool, Settings, or a native menu).
      // Do not infer that it was outside from the global cursor position: keyboard and
      // Accessibility-driven activation can legitimately click without moving the pointer.
      if event.window === self?.panel { self?.isArrowPreview = false }
      self?.recordActivity()
      return event
    }) { eventMonitors.append(monitor) }
    if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
      self?.handleEditorShortcut(event) == true ? nil : event
    }) { eventMonitors.append(monitor) }
    DragMonitor.shared.start()
    parkedInMenuBar = true
    if isPersistent && isEnabled { restoreResident() }
    else { panel?.orderOut(nil); visible = false }
  }

  private func suspendForQuickConvert() {
    guard !suspendedForQuickConvert else { return }
    suspendedForQuickConvert = true
    restoreAfterQuickConvert = visible
    closeFilePreview()
    cancelHide()
    cancelExpansion()
    cancelFolderHover()
    panel?.orderOut(nil)
    visible = false
  }

  private func resumeAfterQuickConvert() {
    guard suspendedForQuickConvert else { return }
    suspendedForQuickConvert = false
    let shouldRestore = restoreAfterQuickConvert
    restoreAfterQuickConvert = false
    guard shouldRestore else { return }
    summon()
  }

  func restoreResident() {
    if quiverAnchor != nil { hideIsland(); return }
    parkedInMenuBar = true
    guard isPersistent, isEnabled, let store else { hideIsland(); return }
    closeFilePreview()
    cancelHide()
    ensurePanel(store: store)
    expanded = false
    showingFolder = false
    showingBin = false
    mediaEditor = false
    focusedBox = nil
    visible = true
    place(on: pointerScreen(), useSaved: false)
    panel?.alphaValue = 1
    panel?.orderFrontRegardless()
  }
  private func hideIsland() {
    cancelHide()
    idleWork?.cancel(); idleWork = nil
    expanded = false
    visible = false
    panel?.orderOut(nil)
  }
  func togglePopup() {
    expanded && isVisible ? dismiss() : summon()
  }
  func toggleDashboard() {
    if visible, expanded, toolsVisible, activeModule == .dashboard { dismiss() }
    else { showModule(.dashboard); focusForKeyboard() }
  }
  func tapCourier() {
    recordActivity()
    cancelFolderHover()
    cancelExpansion()
    controlsVisible.toggle()
    waitForPointerExit = true
    cancelHide()
  }
  func openMainApp() {
    guard !moving, !receiving, store?.busy != true else { return }
    dismiss()
    AppController.shared.openPreferences()
  }
  func openPrimaryFiles() {
    showModule(.parcel)
  }
  func showModule(_ module: NotchModule) {
    recordActivity()
    closeFilePreview()
    if !visible { summon() }
    activeModule = module
    panel?.title = "Skippy · " + module.title
    choosingArrow = false
    toolsVisible = true
    showingFolder = false
    showingBin = false
    mediaEditor = false
    focusedBox = module == .parcel ? primaryBox?.id : nil
    expand()
    fitContents()
  }
  func beginPrimaryDrop() -> FileDropHandler? {
    beginDrop(into: primaryBox?.id, openFiles: showingFolder)
  }
  func showChoices() {
    if parkedInMenuBar || quiverAnchor != nil { showModule(.dashboard); return }
    closeFilePreview()
    focusedBox = nil
    showingFolder = false
    toolsVisible = false
    expand()
    fitContents()
  }
  func presentMediaEditor(itemID: UUID? = nil) {
    guard let store, !store.busy, !receiving else { return }
    if !visible { summon() }
    if let itemID { store.selectedItems = [itemID] }
    if let selected = store.selectedBox { select(selected) }
    if let itemID { store.selectedItems = [itemID] }
    toolsVisible = false
    mediaEditor = true
    fitContents()
  }
  func parkInMenuBar() {
    guard !moving, !receiving, store?.busy != true, store?.phase != .receiving else { return }
    closeFilePreview()
    cancelFolderHover()
    courierHovered = false
    parkedInMenuBar = true
    dismiss()
    if !isPersistent { hideIsland() }
    idleWork?.cancel(); idleWork = nil
  }
  func toggleMenuBar() {
    togglePopup()
  }
  func menuHover(_ inside: Bool, anchor: CGRect, dragging: Bool = false) {
    guard parkedInMenuBar else { return }
    if inside {
      if dragging { showForDrag() }
      else if !visible || !expanded { summon() }
    } else if !pointerInside {
      scheduleHide(after: 0.35)
    }
  }
  func returnFromMenuBar() {
    summon()
  }
  func summon() {
    guard !moving, !receiving, store?.busy != true else { return }
    choosingArrow = false; isArrowPreview = false
    menuAnchor = quiverAnchor?()
    parkedInMenuBar = true
    waitForPointerExit = false
    show(expand: true)
    activeModule = .dashboard
    toolsVisible = true
    showingFolder = false
    showingBin = false
    mediaEditor = false
    focusedBox = primaryBox?.id
    fitContents()
    animateNotchIn()
    awaitingSummonedPointerEntry = panel?.frame.contains(NSEvent.mouseLocation) != true
    panel?.makeKey()
    if let host { panel?.makeFirstResponder(host) }
    Toaster.shared.tip("notch-pages", "Scroll for the next page, / to search, and Tab to move through widgets.")
  }
  func openArrow(_ module: NotchModule, at anchor: CGRect?) {
    if visible && expanded && activeModule == module && toolsVisible && !isArrowPreview {
      dismiss(); return
    }
    presentArrow(module, at: anchor, preview: false)
    focusForKeyboard()
  }

  func previewArrow(_ module: NotchModule, at anchor: CGRect) {
    guard !isVisible || !expanded || isArrowPreview else { return }
    presentArrow(module, at: anchor, preview: true)
  }

  private func presentArrow(_ module: NotchModule, at anchor: CGRect?, preview: Bool) {
    guard !moving, !receiving, store?.busy != true else { return }
    let wasVisible = visible
    menuAnchor = anchor ?? quiverAnchor?()
    parkedInMenuBar = true
    if !wasVisible { show(expand: true) }
    showModule(module)
    isArrowPreview = preview
    if !wasVisible, let panel, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      panel.alphaValue = 0
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.12
        panel.animator().alphaValue = 1
      }
    }
  }

  func dismissArrowPreview() {
    if isArrowPreview { dismiss() }
  }

  func chooseArrow() {
    isArrowPreview = false
    if !toolsVisible { showModule(.dashboard) }
    focusForKeyboard()
    choosingArrow = true
  }
  func cancelChoosingArrow() { choosingArrow = false; focusForKeyboard() }
  func focusForKeyboard() {
    NSApp.activate(ignoringOtherApps: true)
    panel?.makeKey()
    if let host { panel?.makeFirstResponder(host) }
    recordActivity()
  }
  func summonFromMouseShake() {
    summon()
    if visible, expanded {
      awaitingSummonedPointerEntry = true
      cancelHide()
    }
  }
  private func topEdgeHover(at point: CGPoint) {
    guard quiverAnchor == nil, parkedInMenuBar, !visible, !DragMonitor.shared.isDragging,
      let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else {
      topEdgeWork?.cancel(); topEdgeWork = nil; topEdgeLatched = false
      return
    }
    let nearCenterTop = point.y >= screen.frame.maxY - 5
      && abs(point.x - screen.frame.midX) <= min(240, screen.frame.width * 0.2)
    guard nearCenterTop else {
      topEdgeWork?.cancel(); topEdgeWork = nil; topEdgeLatched = false
      return
    }
    guard !topEdgeLatched, topEdgeWork == nil else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.topEdgeWork = nil; self.topEdgeLatched = true; self.summon()
    }
    topEdgeWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
  }
  func showIfDragging() {
    if DragMonitor.shared.isDragging { showForDrag() }
  }
  func showForDrag() {
    guard isEnabled else { return }
    if isVisible && (receiving || store?.busy == true) { return }
    if isVisible {
      if !expanded { showModule(.parcel); animateNotchIn(); return }
      cancelHide()
      followDisplay(NSEvent.mouseLocation)
      panel?.orderFrontRegardless()
    } else {
      parkedInMenuBar = true
      menuAnchor = quiverAnchor?()
      show(expand: true)
      openPrimaryFiles()
      animateNotchIn()
    }
  }
  private func animateNotchIn() {
    guard let panel else { return }
    let target = arrangement.frame
    panel.setFrame(target, display: false)
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      panel.alphaValue = 1; panel.orderFrontRegardless(); return
    }
    panel.setFrame(target.offsetBy(dx: 0, dy: 14), display: false)
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.14
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().setFrame(target, display: true)
      panel.animator().alphaValue = 1
    }
  }
  private func show(expand: Bool) {
    guard !moving else { return }
    guard let store else { return }
    closeFilePreview()
    if receiving || store.busy || store.phase == .receiving {
      self.expand()
      panel?.orderFrontRegardless()
      return
    }
    cancelHide()
    cancelPreview()
    ensurePanel(store: store)
    generation += 1
    intakeCount = 0
    intakeBox = nil
    hasReceipt = false
    controlsVisible = false
    focusedBox = nil
    showingFolder = false
    showingBin = false
    mediaEditor = false
    toolsVisible = false
    activeModule = .dashboard
    failed = false
    statusVisible = false
    message = "Put files down. Pick them up anywhere."
    destinations = []
    expanded = expand
    visible = true
    waitForPointerExit = false
    courierHovered = false
    reveal += 1
    pointerInside = false
    place(on: pointerScreen(), useSaved: true)
    panel?.alphaValue = 1
    panel?.orderFrontRegardless()
    pointerInside = panel?.frame.contains(NSEvent.mouseLocation) == true
    recordActivity()
  }

  func expand() {
    guard !moving else { return }
    cancelExpansion()
    cancelHide()
    guard !expanded else { return }
    expanded = true
    reveal += 1
    resizeKeepingAnchor()
  }
  func hoverChanged(_ inside: Bool) {
    guard !moving else { return }
    if inside {
      awaitingSummonedPointerEntry = false
      recordActivity()
      pointerInside = true
      cancelHide()
      guard !waitForPointerExit, (!expanded || showingFolder), expandWork == nil, incoming || DragMonitor.shared.isDragging else { return }
      let work = DispatchWorkItem { [weak self] in
        guard let self, self.pointerInside, !self.waitForPointerExit else { return }
        self.showChoices()
      }
      expandWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay, execute: work)
    } else {
      guard !awaitingSummonedPointerEntry else { return }
      guard panel?.frame.contains(NSEvent.mouseLocation) != true else { return }
      pointerInside = false
      courierHovered = false
      cancelFolderHover()
      waitForPointerExit = false
      cancelExpansion()
      cancelPreview()
      scheduleHide(after: 0.35)
    }
  }
  func dragHoverChanged(_ inside: Bool) {
    incoming = inside
    cancelFolderHover()
    hoverChanged(inside)
  }
  func courierHoverChanged(_ inside: Bool) {
    guard !moving else { return }
    let entered = inside && !courierHovered
    courierHovered = inside
    hoverChanged(inside)
    if !inside { cancelFolderHover(); return }
    if parkedInMenuBar, entered, !incoming, !DragMonitor.shared.isDragging,
      !receiving, store?.busy == false {
      showModule(.dashboard)
      return
    }
    guard entered, !controlsVisible, !showingFolder, !showingBin, !mediaEditor, !receiving,
      store?.busy == false, !incoming, !DragMonitor.shared.isDragging, let primaryID = primaryBox?.id else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.courierHovered, !self.waitForPointerExit, !self.moving,
        !self.receiving, self.store?.busy == false, !self.incoming, !DragMonitor.shared.isDragging,
        !self.showingFolder, !self.showingBin, !self.mediaEditor,
        self.primaryBox?.id == primaryID else { return }
      self.select(primaryID)
    }
    folderWork = work
    if folderHoverDelay <= 0 { work.perform() }
    else { DispatchQueue.main.asyncAfter(deadline: .now() + folderHoverDelay, execute: work) }
  }
  private func cancelFolderHover() { folderWork?.cancel(); folderWork = nil }
  private func trackPointer() {
    guard let panel, visible, !moving else { return }
    let inside = panel.frame.contains(NSEvent.mouseLocation)
    if quiverPointerInside != inside {
      quiverPointerInside = inside
      quiverPanelPointer?(inside)
    }
    if waitForPointerExit {
      if !inside { waitForPointerExit = false }
      pointerInside = inside
      return
    }
    if inside {
      hoverChanged(true)
    } else {
      hoverChanged(false)
    }
    pointerInside = inside
  }
  private func cancelExpansion() { expandWork?.cancel(); expandWork = nil }
  private func followDisplay(_ point: NSPoint) {
    guard visible, !pointerInside, !receiving, !hasReceipt, let screen = NSScreen.screens.first(where: {
      $0.frame.contains(point)
    }), screen != panel?.screen else { return }
    place(on: screen, useSaved: true)
    panel?.orderFrontRegardless()
  }

  func beginDrop(into destination: UUID?, openFiles: Bool = true) -> FileDropHandler? {
    guard let store, !store.busy, !receiving, !store.needsLibraryRecovery else { return nil }
    closeFilePreview()
    cancelPreview()
    cancelFolderHover()
    guard let boxID = store.shelfDestination(destination) else { return nil }
    focusedBox = boxID
    showingFolder = openFiles
    hasReceipt = true
    failed = false
    expand()
    resizeKeepingAnchor()
    var errors: [String] = []
    return FileDropHandler(
      receive: { [weak self, weak store] urls in
        guard let self, let store else { return }
        let before = store.boxes.first(where: { $0.id == boxID })?.items.count ?? 0
        store.error = nil
        store.ingest(urls, into: boxID)
        let after = store.boxes.first(where: { $0.id == boxID })?.items.count ?? before
        if let error = store.error { errors.append(error) }
        store.error = nil
        self.finishIntake(added: after - before, error: errors.isEmpty ? nil : errors.joined(separator: "\n"))
      },
      receiveText: { [weak self, weak store] text in
        guard let self, let store else { return }
        store.error = nil
        store.ingestText(text, into: boxID)
        if let error = store.error { errors.append(error) }
        store.error = nil
        self.finishIntake(added: 1, error: errors.isEmpty ? nil : errors.joined(separator: "\n"))
      },
      receiving: { [weak self, weak store] started in
        self?.receiving = started
        if started {
          self?.cancelHide()
          self?.showingFolder = true
          self?.fitContents()
          self?.message = "Receiving your pieces…"
          store?.beginReceiving()
        } else {
          store?.endReceiving()
          if self?.message == "Receiving your pieces…" {
            self?.message = "Received. Pick up your pieces, or pack them together."
          }
          self?.scheduleHide(after: 1.2)
        }
      },
      failure: { [weak self] error in
        errors.append(error)
        self?.finishIntake(added: 0, error: errors.joined(separator: "\n"))
      })
  }
  private func finishIntake(added: Int, error: String?) {
    if added > 0 {
      intakeCount = min(3, added)
      intakeBox = focusedBox
      intakeEvent += 1
    }
    failed = error != nil
    if error != nil { showingFolder = true; fitContents() }
    statusVisible = true
    message = error ?? (added == 0 ? "Already tucked safely in this parcel." : "Tucked in. Keep going, or pack it up.")
    reveal += 1
    if added > 0 { Toaster.shared.tip("drag-name", "Drag the parcel name to pack a ZIP and send it anywhere.") }
    scheduleHide(after: 1.2)
  }
  func select(_ boxID: UUID) {
    hideSearch()
    closeFilePreview()
    cancelPreview()
    cancelFolderHover()
    guard let store, !store.busy, !receiving, store.phase != .receiving,
      store.boxes.contains(where: { $0.id == boxID }) else { return }
    if store.selectedBox != boxID { store.selectBox(boxID) }
    store.selectedItems = []
    keyboardFocusedItem = nil
    focusedBox = boxID
    showingFolder = true
    hasReceipt = true
    failed = false
    statusVisible = false
    message = "Pick up your pieces, or pack them together."
    expand()
    resizeKeepingAnchor()
    recordActivity()
  }
  func preview(_ boxID: UUID, hovering: Bool) {
    guard showingFolder else { return }
    if !hovering {
      if pendingPreview == boxID { cancelPreview() }
      return
    }
    if pendingPreview == boxID { return }
    cancelPreview()
    guard boxID != focusedBox, !receiving, store?.busy == false else { return }
    pendingPreview = boxID
    let stamp = generation
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.generation == stamp, self.pendingPreview == boxID else { return }
      self.select(boxID)
    }
    previewWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
  }
  private func cancelPreview() { previewWork?.cancel(); previewWork = nil; pendingPreview = nil }
  func togglePin(_ boxID: UUID) {
    store?.toggleParcelPin(boxID)
    cancelFolderHover()
    destinations = []
  }
  func moveToBin(_ boxID: UUID) {
    guard let store, !receiving, !store.busy, store.phase != .receiving,
      !store.needsLibraryRecovery else { return }
    store.error = nil
    store.moveToBin(boxID)
    if let error = store.error { store.error = nil; report(error); return }
    if focusedBox == boxID { focusedBox = nil }
    resizeKeepingAnchor()
    destinations = []
    message = "Moved to Bin. Restore it within 30 days. Originals are untouched."
    failed = false
    statusVisible = true
  }
  func removeItem(_ itemID: UUID, from boxID: UUID) {
    removeItems([itemID], from: boxID)
  }
  private func removeItems(_ itemIDs: Set<UUID>, from boxID: UUID) {
    guard let store, !receiving, !store.busy, store.phase != .receiving,
      store.boxes.contains(where: { box in box.id == boxID && box.items.contains(where: { itemIDs.contains($0.id) }) }) else { return }
    if store.selectedBox != boxID { store.selectBox(boxID) }
    store.remove(itemIDs)
    keyboardFocusedItem = nil
    closeFilePreview()
    message = itemIDs.count == 1
      ? "Removed from this parcel. The original file is untouched."
      : "Stack removed from this parcel. The original files are untouched."
    failed = false
    statusVisible = true
    fitContents()
  }
  func beginItemDeleteDrop(_ itemID: UUID, from boxID: UUID) -> FileDropHandler? {
    guard let store, let box = store.boxes.first(where: { $0.id == boxID }),
      let item = box.items.first(where: { $0.id == itemID }),
      !store.busy, !receiving else { return nil }
    let members = store.stackMembers(of: item, in: box)
    let expected = Set(members.map { $0.effectiveURL.standardizedFileURL })
    let memberIDs = Set(members.map(\.id))
    return FileDropHandler(receive: { [weak self] urls in
      guard Set(urls.map { $0.standardizedFileURL }).isSuperset(of: expected) else {
        self?.feedback("Drop the highlighted parcel item here to remove it.", isError: true)
        return
      }
      self?.removeItems(memberIDs, from: boxID)
    }, receiveText: { [weak self] _ in
      self?.feedback("Only parcel items can be removed here.", isError: true)
    }, receiving: { _ in }, failure: { [weak self] error in self?.feedback(error, isError: true) })
  }
  func copyFiles(item: UUID? = nil) {
    guard let store, let focusedBox, !receiving else { return }
    if item == nil, store.selectedBox == focusedBox, store.ready {
      if store.copyArchiveToClipboard() {
        failed = false; statusVisible = true
        message = "Packed parcel copied as one ZIP. Paste it into another parcel or app."
        reveal += 1
      } else { report("The packed parcel could not be copied.") }
      return
    }
    do {
      let count = try store.copyShelfFiles(in: focusedBox, itemID: item, matchingSearch: item == nil && store.isSearching)
      failed = false
      statusVisible = true
      message = "Copied \(count) piece\(count == 1 ? "" : "s"). Pack first to copy one parcel ZIP."
      reveal += 1
    } catch { report(error.localizedDescription) }
  }
  private func handleEditorShortcut(_ event: NSEvent) -> Bool {
    guard event.window === panel, let editor = panel?.firstResponder as? NSTextView,
          event.modifierFlags.intersection([.command, .shift, .control, .option]) == .command else { return false }
    switch event.charactersIgnoringModifiers?.lowercased() {
    case "a": editor.selectAll(nil)
    case "c": editor.copy(nil)
    case "x" where editor.isEditable: editor.cut(nil)
    case "v" where editor.isEditable: editor.paste(nil)
    default: return false
    }
    return true
  }

  @discardableResult func handleCourierKey(_ event: NSEvent) -> Bool {
    guard visible, expanded, !showingBin, !mediaEditor,
      let command = CourierShortcutStore.shared.command(for: event) else { return false }
    if choosingArrow {
      if command == .close || command == .chooseArrow { cancelChoosingArrow(); return true }
      return false
    }
    switch command {
    case .browsePins:
      SkippyQuiver.shared.beginKeyboardBrowsing()
      return true
    case .cycleTheme:
      SkinStore.shared.skin = SkinStore.shared.skin == .night ? .kraft : .night
      return true
    case .cycleEmblem:
      let icons = QuiverEmblem.allCases
      let index = icons.firstIndex(of: SkippyQuiver.shared.emblem) ?? 0
      SkippyQuiver.shared.emblem = icons[(index + 1) % icons.count]
      return true
    case .chooseArrow: chooseArrow(); return true
    default: break
    }
    if panel?.firstResponder is NSTextView {
      switch command {
      case .search, .filters, .nextFile, .previousFile, .open, .copy, .paste: return false
      default: break
      }
    }
    if toolsVisible {
      if (command == .copy || command == .paste) && activeModule != .parcel && activeModule != .dashboard { return false }
      switch command {
      case .chooseArrow, .cycleTheme, .cycleEmblem, .browsePins: break
      case .nextFile:
        guard activeModule == .dashboard else { return false }
        NotificationCenter.default.post(name: .parcelsNextWidgetPage, object: nil)
      case .previousFile:
        guard activeModule == .dashboard else { return false }
        NotificationCenter.default.post(name: .parcelsPreviousWidgetPage, object: nil)
      case .search: showModule(.search)
      case .filters:
        ClipboardHistoryStore.shared.cycleFilter()
        showModule(.clipboard)
      case .pack:
        focusedBox = primaryBox?.id
        pack()
      case .copy:
        focusedBox = primaryBox?.id
        copyFiles()
      case .paste:
        focusedBox = primaryBox?.id
        pasteFiles()
      case .clipboard: showModule(activeModule == .clipboard ? .dashboard : .clipboard)
      case .tools: showModule(.dashboard)
      case .processMedia:
        focusedBox = primaryBox?.id
        presentMediaEditor()
      case .ocr: showModule(.extract)
      case .settings: AppController.shared.openPreferences()
      case .open:
        guard activeModule == .dashboard || activeModule == .parcel else { return false }
        showModule(.parcel)
      case .close: dismiss()
      }
      return true
    }
    if isClipboardVisible {
      switch command {
      case .clipboard, .close: hideClipboard(); return true
      case .search:
        NotificationCenter.default.post(name: .parcelFocusClipboardSearch, object: nil); return true
      case .filters: ClipboardHistoryStore.shared.cycleFilter(); return true
      default: break
      }
    }
    if isSearchVisible {
      switch command {
      case .search: NotificationCenter.default.post(name: .parcelFocusCourierSearch, object: nil); return true
      case .filters: NotificationCenter.default.post(name: .parcelShowCourierFilters, object: nil); return true
      case .close: hideSearch(clear: true); return true
      default: break
      }
    }
    if command == .clipboard { toggleClipboard(); return true }
    if command == .tools { showModule(.dashboard); return true }
    if command == .search { showSearch(); return true }
    if command == .filters { showSearch(showFilters: true); return true }
    guard showingFolder else { return false }
    if command == .paste, panel?.firstResponder is NSTextView { return false }
    recordActivity()
    switch command {
    case .cycleTheme, .cycleEmblem, .browsePins: break
    case .chooseArrow: chooseArrow()
    case .nextFile: moveKeyboardFocus(1)
    case .previousFile: moveKeyboardFocus(-1)
    case .search, .filters: break
    case .pack: pack()
    case .copy: copyFiles(item: keyboardFocusedItem)
    case .paste: pasteFiles()
    case .clipboard: break
    case .tools: showModule(.dashboard)
    case .processMedia: presentMediaEditor(itemID: keyboardFocusedItem)
    case .ocr: store?.extractTextFromImages(itemIDs: keyboardFocusedItem.map { [$0] })
    case .settings: AppController.shared.openPreferences()
    case .open:
      if let item = keyboardFocusedParcelItem { openFile(item) }
    case .close: dismiss()
    }
    return true
  }
  private var keyboardFocusedParcelItem: ParcelItem? {
    guard let store, let focusedBox, let id = keyboardFocusedItem else { return nil }
    return store.boxes.first(where: { $0.id == focusedBox })?.items.first(where: { $0.id == id })
  }
  private func moveKeyboardFocus(_ step: Int) {
    guard let store, let focusedBox, let box = store.boxes.first(where: { $0.id == focusedBox }) else { return }
    let items = store.filteredItems(in: box)
    guard !items.isEmpty else { keyboardFocusedItem = nil; store.selectedItems = []; filePreview.clear(); return }
    let current = keyboardFocusedItem.flatMap { id in items.firstIndex(where: { $0.id == id }) }
    let index = current.map { ($0 + step % items.count + items.count) % items.count } ?? (step < 0 ? items.count - 1 : 0)
    let item = items[index]
    keyboardFocusedItem = item.id
    store.selectedItems = [item.id]
    filePreview.focus(item)
  }
  func openFile(_ item: ParcelItem) {
    guard let store, let focusedBox, !store.busy, !receiving else { return }
    do {
      let url = try store.shelfFileURLs(in: focusedBox, itemID: item.id)[0]
      if !NSWorkspace.shared.open(url) { report("No application could open \(item.effectiveName). Try Reveal in Finder.") }
    } catch { report(error.localizedDescription) }
  }
  func pasteFiles() {
    let destination = toolsVisible && activeModule == .parcel ? primaryBox?.id : focusedBox
    guard let store, let destination, !receiving, !store.busy, store.phase != .receiving else { return }
    store.selectBox(destination)
    store.error = nil
    store.paste()
    if let error = store.error { store.error = nil; report(error) }
    else { message = store.notice ?? "Clipboard pieces tucked into your parcel."; failed = false }
  }
  private func report(_ error: String) { failed = true; statusVisible = true; message = error; expand() }
  func feedback(_ text: String, isError: Bool = false) {
    failed = isError; statusVisible = true; message = text
  }
  func clipboardHoverChanged(_ inside: Bool) {
    clipboardHoverActive = inside
    clipboardHideWork?.cancel(); clipboardHideWork = nil
    guard inside else {
      guard !clipboardPinnedOpen else { return }
      let work = DispatchWorkItem { [weak self] in
        guard let self, !self.clipboardHoverActive else { return }
        self.hideClipboard()
      }
      clipboardHideWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
      return
    }
    guard let panel else { return }
    recordActivity()
    guard clipboard.panel?.isVisible != true else { return }
    clipboard.show(parent: panel, skin: SkinStore.shared.skin,
      hover: { [weak self] in self?.clipboardHoverChanged($0) }, close: { [weak self] in self?.hideClipboard() },
      addToParcel: { [weak self] in self?.addClipboardEntry($0) },
      processImage: { [weak self] in self?.processClipboardImage($0) },
      keyHandler: { [weak self] in self?.handleCourierKey($0) == true })
  }
  func hideClipboard() {
    clipboardPinnedOpen = false
    clipboardHideWork?.cancel(); clipboardHideWork = nil
    clipboard.hide()
  }
  func toggleClipboard() {
    if clipboard.panel?.isVisible == true, clipboardPinnedOpen { hideClipboard() }
    else { clipboardPinnedOpen = true; clipboardHoverChanged(true) }
  }
  func showSearch(showFilters: Bool = false) {
    guard let store, let focusedBox, let panel else { return }
    searchHideWork?.cancel(); searchHideWork = nil
    searchPanel.show(store: store, boxID: focusedBox, parent: panel, skin: SkinStore.shared.skin,
      inside: { [weak self] in self?.searchHoverChanged($0) },
      close: { [weak self] in self?.hideSearch(clear: true) }, open: { [weak self] in self?.openFile($0) },
      menu: { [weak self] in self?.fileContextMenu(for: $0) ?? NSMenu() },
      keyHandler: { [weak self] in self?.handleCourierKey($0) == true })
    NotificationCenter.default.post(name: .parcelFocusCourierSearch, object: nil)
    if showFilters { DispatchQueue.main.async { NotificationCenter.default.post(name: .parcelShowCourierFilters, object: nil) } }
  }
  func searchHoverChanged(_ inside: Bool) {
    searchHideWork?.cancel(); searchHideWork = nil
    if inside {
      recordActivity()
      if !isSearchVisible { showSearch() }
    } else {
      guard !searchPinnedOpen else { return }
      let work = DispatchWorkItem { [weak self] in
        guard let self, self.searchPanel.panel?.frame.contains(NSEvent.mouseLocation) != true else { return }
        self.hideSearch(clear: false)
      }
      searchHideWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
  }
  func toggleSearch() {
    if isSearchVisible, searchPinnedOpen { hideSearch(clear: true) }
    else { searchPinnedOpen = true; showSearch() }
  }
  func hideSearch(clear: Bool = false) {
    searchPinnedOpen = false
    searchHideWork?.cancel(); searchHideWork = nil; searchPanel.hide()
    if clear { store?.clearFileSearch() }
  }
  func optionsHoverChanged(_ inside: Bool, delete: @escaping () -> Void) {
    optionsHideWork?.cancel(); optionsHideWork = nil
    if inside {
      recordActivity()
      guard !isOptionsVisible else { return }
      guard let store, let focusedBox, let panel else { return }
      optionsPanel.show(store: store, boxID: focusedBox, parent: panel, skin: SkinStore.shared.skin,
        viewStyle: viewStyle, setViewStyle: { [weak self] in self?.viewStyle = $0 },
        hover: { [weak self] in self?.optionsHoverChanged($0, delete: delete) },
        paste: { [weak self] in self?.pasteFiles() },
        openBin: { [weak self] in self?.showingBin = true; self?.fitContents() }, delete: delete,
        settings: { AppController.shared.openPreferences() }, close: { [weak self] in self?.hideOptions() })
    } else {
      guard !optionsPinnedOpen else { return }
      let work = DispatchWorkItem { [weak self] in
        guard let self, self.optionsPanel.panel?.frame.contains(NSEvent.mouseLocation) != true else { return }
        self.hideOptions()
      }
      optionsHideWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
  }
  func toggleOptions(delete: @escaping () -> Void) {
    if isOptionsVisible, optionsPinnedOpen { hideOptions() }
    else { optionsPinnedOpen = true; optionsHoverChanged(true, delete: delete) }
  }
  func hideOptions() {
    optionsPinnedOpen = false
    optionsHideWork?.cancel(); optionsHideWork = nil
    optionsPanel.hide()
  }
  func addClipboardEntry(_ entry: ClipboardEntry) {
    guard let handler = beginDrop(into: focusedBox ?? primaryBox?.id) else { return }
    if let text = entry.dragText { handler.receiveText(text) }
    else if !entry.dragURLs.isEmpty { handler.receive(entry.dragURLs) }
  }
  func processClipboardImage(_ entry: ClipboardEntry) {
    guard entry.kind == .image, let url = entry.dragURLs.first,
      let handler = beginDrop(into: focusedBox ?? primaryBox?.id) else { return }
    handler.receive([url])
    guard let store, let boxID = focusedBox,
      let item = store.boxes.first(where: { $0.id == boxID })?.items.first(where: {
        $0.sourceURL.standardizedFileURL == url.standardizedFileURL
      }) else { return }
    store.selectBox(boxID)
    presentMediaEditor(itemID: item.id)
    hideClipboard()
  }

  func fileContextMenu(for item: ParcelItem) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    let available = FileManager.default.fileExists(atPath: item.effectiveURL.path)
    menu.addItem(CourierMenuAction("Open", enabled: available) { [weak self] in self?.openFile(item) })
    menu.addItem(CourierMenuAction("Quick Look", enabled: available) {
      QuickLookController.shared.show([item.effectiveURL])
    })
    let box = store?.boxes.first(where: { $0.id == focusedBox })
    let stackCount = box.map { store?.stackCount(of: item, in: $0) ?? 1 } ?? 1
    menu.addItem(CourierMenuAction(stackCount > 1 ? "Copy stack (\(stackCount) items)" : "Copy item",
      enabled: available && store?.canExport == true) { [weak self] in
      self?.copyFiles(item: item.id)
    })
    menu.addItem(CourierMenuAction("Copy all parcel items", enabled: store?.canExport == true) { [weak self] in
      self?.copyFiles()
    })
    menu.addItem(CourierMenuAction("Pack parcel", enabled: !receiving && store?.busy == false) { [weak self] in self?.pack() })
    menu.addItem(CourierMenuAction("Save packed parcel to Desktop", enabled: !receiving && store?.busy == false) { [weak self] in
      self?.savePackedParcelToDesktop()
    })
    if ImagePipeline.canPrepare(item.effectiveURL) {
      menu.addItem(.separator())
      menu.addItem(CourierMenuAction("Process image…", enabled: !receiving && store?.busy == false) { [weak self] in
        self?.presentMediaEditor(itemID: item.id)
      })
      menu.addItem(CourierMenuAction("Copy text with OCR", enabled: !receiving && store?.busy == false) { [weak self] in
        self?.store?.extractTextFromImages(itemIDs: [item.id])
      })
    }
    if VideoPipeline.canPrepare(item.effectiveURL) {
      menu.addItem(.separator())
      menu.addItem(CourierMenuAction("Process video…", enabled: !receiving && store?.busy == false) { [weak self] in
        self?.presentMediaEditor(itemID: item.id)
      })
    }
    menu.addItem(.separator())
    if stackCount > 1 {
      menu.addItem(CourierMenuAction("Unstack items", enabled: store?.busy == false) { [weak self] in self?.store?.unstack(item.id) })
    }
    menu.addItem(CourierMenuAction("Reveal in Finder", enabled: available) {
      NSWorkspace.shared.activateFileViewerSelecting([item.effectiveURL])
    })
    return menu
  }
  func renameParcel(_ boxID: UUID) {
    guard let store, let box = store.boxes.first(where: { $0.id == boxID }), !store.busy, !receiving else { return }
    confirmationChanged(true)
    defer { confirmationChanged(false) }
    let alert = NSAlert()
    alert.messageText = "Rename parcel"
    alert.addButton(withTitle: "Rename")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(string: box.name)
    field.frame = CGRect(x: 0, y: 0, width: 260, height: 26)
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    NSApp.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    store.selectBox(boxID)
    store.renameBox(field.stringValue)
    if let error = store.error { store.error = nil; report(error) }
  }
  func preparePrimaryArchive(_ completion: @escaping (URL?) -> Void) {
    guard let primary = primaryBox else { completion(nil); return }
    prepareArchive(for: primary.id, completion)
  }
  func prepareArchive(for boxID: UUID, _ completion: @escaping (URL?) -> Void) {
    guard let store, let box = store.boxes.first(where: { $0.id == boxID }),
      !store.busy, !receiving, !box.items.isEmpty else {
      completion(nil); return
    }
    store.refreshLicense()
    guard store.canExport else { feedback("An active licence is needed to pack or share.", isError: true); completion(nil); return }
    if store.selectedBox != box.id { store.selectBox(box.id) }
    var options = store.packaging
    options.saveToDesktop = false
    if store.ready, let archive = store.archiveURL,
      archive.pathExtension.lowercased() == options.format.fileExtension,
      FileManager.default.fileExists(atPath: archive.path) { completion(archive); return }
    focusedBox = box.id
    store.seal(reportError: { [weak self] in self?.feedback($0, isError: true) }, options: options, finished: completion)
  }
  func contextMenu(for view: NSView) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    let canPack = !receiving && store?.busy == false && primaryBox?.items.isEmpty == false
    menu.addItem(CourierMenuAction("Share parcel…", enabled: canPack) { [weak self, weak view] in
      self?.preparePrimaryArchive { [weak self, weak view] archive in
        guard let self, let view, let archive else { return }
        let picker = NSSharingServicePicker(items: [archive])
        self.sharingPicker = picker
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
      }
    })
    menu.addItem(CourierMenuAction("Copy ZIP to WhatsApp…", enabled: canPack) { [weak self] in
      self?.preparePrimaryArchive { [weak self] archive in
        guard archive != nil else { return }
        self?.store?.shareViaWhatsApp()
      }
    })
    menu.addItem(CourierMenuAction("Copy packed parcel", enabled: canPack) { [weak self] in
      self?.preparePrimaryArchive { [weak self] archive in
        guard archive != nil else { return }
        self?.store?.copyArchiveToClipboard()
      }
    })
    menu.addItem(.separator())
    menu.addItem(CourierMenuAction("Open files", action: openPrimaryFiles))
    menu.addItem(CourierMenuAction("Open Settings", action: openMainApp))
    menu.addItem(CourierMenuAction("Courier settings…") { AppController.shared.openPreferences() })
    menu.addItem(CourierMenuAction("Collapse Skippy", action: parkInMenuBar))
    menu.addItem(CourierMenuAction("Quit Skippy") { NSApp.terminate(nil) })
    return menu
  }
  func pack() {
    guard let store, let focusedBox, !receiving, !store.busy else { return }
    store.selectBox(focusedBox)
    store.error = nil
    store.seal(reportError: { [weak self] error in
      self?.failed = true
      self?.message = error
    })
    Toaster.shared.tip("copy-packed", "After packing, ⌘C copies the parcel as one ZIP.")
    cancelHide()
  }
  func saveArchive() {
    guard let store else { return }
    store.saveArchive()
    if let error = store.error {
      store.error = nil
      failed = true
      message = error
    } else { message = store.notice ?? "Saved. Ready for the next stop." }
  }
  func savePackedParcelToDesktop() {
    guard let boxID = focusedBox else { return }
    prepareArchive(for: boxID) { [weak self] archive in
      guard let self, let archive,
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else { return }
      var destination = desktop.appendingPathComponent(archive.lastPathComponent)
      var suffix = 2
      while FileManager.default.fileExists(atPath: destination.path) {
        let stem = (archive.lastPathComponent as NSString).deletingPathExtension
        destination = desktop.appendingPathComponent("\(stem) (\(suffix)).\(archive.pathExtension)")
        suffix += 1
      }
      do {
        try FileManager.default.copyItem(at: archive, to: destination)
        self.feedback("Saved \(destination.lastPathComponent) to Desktop.")
      } catch { self.feedback(error.localizedDescription, isError: true) }
    }
  }

  func beginPopupMove() {
    guard !moving else { return }
    closeFilePreview()
    movingCourierFrame = arrangement.courier
    moving = true
    cancelHide()
    cancelExpansion()
    cancelFolderHover()
    courierHovered = false
    cancelPreview()
  }
  func movePopup(with event: NSEvent) {
    guard let panel, moveCompletion == nil else { return }
    beginPopupMove()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0
      panel.animator().setFrame(panel.frame, display: false)
    }
    let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        if NSEvent.pressedMouseButtons & 1 == 0 { self?.finishPopupMove() }
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    moveCompletion = timer
    panel.performDrag(with: event)
  }
  func finishPopupMove() {
    guard moving else { return }
    moveCompletion?.invalidate()
    moveCompletion = nil
    if let frame = panel?.frame {
      let courier = (movingCourierFrame ?? arrangement.courier).offsetBy(dx: frame.minX, dy: frame.minY)
      topRight = CGPoint(x: courier.maxX, y: courier.maxY)
      if let screen = panel?.screen {
        displayPositions.save(topRight!, displayID: Self.displayID(for: screen), separate: remembersPositionPerDisplay)
      }
      placementScreen = panel?.screen?.visibleFrame
    }
    moving = false
    movingCourierFrame = nil
    if pendingMoveLayout {
      pendingMoveLayout = false
      resizeKeepingAnchor()
    }
    pointerInside = panel?.frame.contains(NSEvent.mouseLocation) == true
    waitForPointerExit = pointerInside
    if !pointerInside { scheduleHide(after: 0.45) }
  }
  func dismiss() {
    guard !moving, !receiving, store?.busy != true, store?.phase != .receiving,
      !DragMonitor.shared.isSending else { return }
    closeFilePreview()
    isArrowPreview = false; choosingArrow = false
    if quiverPointerInside { quiverPointerInside = false; quiverPanelPointer?(false) }
    awaitingSummonedPointerEntry = false
    hideClipboard()
    hideSearch()
    hideOptions()
    searchHideWork?.cancel(); searchHideWork = nil
    cancelHide()
    cancelExpansion()
    cancelFolderHover()
    cancelPreview()
    generation += 1
    focusedBox = nil
    controlsVisible = false
    showingFolder = false
    showingBin = false
    mediaEditor = false
    toolsVisible = false
    activeModule = .dashboard
    hasReceipt = false
    failed = false
    statusVisible = false
    if quiverAnchor != nil { hideIsland(); return }
    if parkedInMenuBar, isPersistent, isEnabled {
      expanded = false
      visible = true
      waitForPointerExit = false
      guard let panel else { return }
      let target = arrangement.frame
      panel.orderFrontRegardless()
      if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        panel.setFrame(target, display: true); panel.alphaValue = 1
      } else {
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.16
          context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
          panel.animator().setFrame(target, display: true)
          panel.animator().alphaValue = 1
        }
      }
      return
    }
    if !parkedInMenuBar {
      expanded = false
      waitForPointerExit = pointerInside
      resizeKeepingAnchor()
      return
    }
    let stamp = generation
    visible = false
    guard let panel else { return }
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      panel.orderOut(nil)
    } else {
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.13
        panel.animator().alphaValue = 0
      }, completionHandler: { [weak self] in
        MainActor.assumeIsolated {
          if self?.generation == stamp { panel.orderOut(nil) }
        }
      })
    }
  }
  private func cancelHide() { hideWork?.cancel(); hideWork = nil }
  func recordActivity() {
    lastActivity = ProcessInfo.processInfo.systemUptime
    guard visible, idleTimeout > 0, idleWork == nil else { return }
    scheduleIdle(after: idleTimeout)
  }
  private func scheduleIdle(after delay: TimeInterval) {
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.idleWork = nil
      guard self.visible, self.idleTimeout > 0 else { return }
      let usingAuxiliaryPanel = self.clipboardPinnedOpen || self.searchPinnedOpen || self.optionsPinnedOpen
      if self.receiving || self.store?.busy == true || self.confirmingAction || self.selectingOnScreen || self.moving || !self.trackedMenus.isEmpty || DragMonitor.shared.isSending || self.filePreview.isInsidePreview || usingAuxiliaryPanel {
        self.recordActivity(); return
      }
      let remaining = self.idleTimeout - (ProcessInfo.processInfo.systemUptime - self.lastActivity)
      if remaining > 0 { self.scheduleIdle(after: remaining) } else { self.dismiss() }
    }
    idleWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }
  /// A system picker owns the next click. Keep the tool's contents and uncover the target pixel.
  func beginScreenSelection() -> @MainActor () -> Void {
    guard isVisible else { return {} }
    selectingOnScreen = true
    isArrowPreview = false
    let stamp = generation
    panel?.orderOut(nil)
    return { [weak self] in
      guard let self else { return }
      self.selectingOnScreen = false
      self.selectionEndedAt = ProcessInfo.processInfo.systemUptime
      guard self.visible, self.generation == stamp else { return }
      self.panel?.orderFrontRegardless()
      self.focusForKeyboard()
    }
  }

  func confirmationChanged(_ presented: Bool) {
    recordActivity()
    confirmingAction = presented
    if presented {
      closeFilePreview()
      cancelHide()
      cancelExpansion()
      cancelFolderHover()
    } else { scheduleHide(after: 0.45) }
  }
  func menuTrackingChanged(_ menu: NSMenu, active: Bool) {
    recordActivity()
    let identity = ObjectIdentifier(menu)
    if active {
      guard visible || expanded else { return }
      trackedMenus.insert(identity)
      cancelFolderHover()
      cancelExpansion()
      cancelHide()
    } else if trackedMenus.remove(identity) != nil, trackedMenus.isEmpty {
      scheduleHide(after: 0.45)
    }
  }
  private func scheduleHide(after delay: TimeInterval) {
    cancelHide()
    guard !toolsVisible, !awaitingSummonedPointerEntry, !confirmingAction, trackedMenus.isEmpty,
      !moving, !receiving, store?.busy != true else { return }
    let stamp = generation
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.generation == stamp else { return }
      if self.awaitingSummonedPointerEntry || self.pointerInside || self.filePreview.item != nil || self.panel?.isKeyWindow == true
        || self.clipboard.panel?.isVisible == true || self.searchPanel.panel?.isVisible == true
        || self.optionsPanel.panel?.isVisible == true
        || DragMonitor.shared.isDragging || DragMonitor.shared.isSending {
        self.scheduleHide(after: 0.45)
        return
      }
      self.dismiss()
    }
    hideWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }
  private func pointerScreen() -> NSScreen? {
    NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
      ?? NSScreen.main ?? NSScreen.screens.first
  }
  static func displayID(for screen: NSScreen) -> String {
    if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
      return number.stringValue
    }
    return "\(screen.localizedName)|\(Int(screen.frame.minX)),\(Int(screen.frame.minY)),\(Int(screen.frame.width)),\(Int(screen.frame.height))"
  }
  var connectedDisplayNames: [String] { NSScreen.screens.map(\.localizedName) }
  func resetDisplayPositions() {
    displayPositions.reset()
    topRight = nil
    place(on: pointerScreen(), useSaved: false)
  }
  private func place(on screen: NSScreen?, useSaved: Bool) {
    guard let screen else { return }
    let frame = screen.visibleFrame
    placementScreen = frame
    placementPhysicalScreen = screen.frame
    objectWillChange.send()
    topRight = topCenterAnchor(in: frame)
    if useSaved, let anchor = displayPositions.anchor(
      displayID: Self.displayID(for: screen), frame: frame, separate: remembersPositionPerDisplay) {
      topRight = anchor
    }
    clampAnchor()
    resizeKeepingAnchor()
  }
  private func topCenterAnchor(in frame: CGRect) -> CGPoint {
    CGPoint(x: frame.midX + physicalCourierSize.width / 2, y: frame.maxY - 12)
  }
  private func collapseForOutsideClick(at point: CGPoint, timestamp: TimeInterval) {
    guard !selectingOnScreen, timestamp > selectionEndedAt else { return }
    guard visible, expanded, !moving, !confirmingAction, trackedMenus.isEmpty,
      store?.busy != true, !receiving else { return }
    // Tool modules are explicitly opened, not hover previews. Keep them pinned until
    // Close/Escape or the configured idle policy retracts the notch.
    if toolsVisible && quiverAnchor == nil { return }
    let insideCourier = panel?.frame.contains(point) == true
    let insidePreview = sidePreview.panel?.frame.contains(point) == true
    let insideClipboard = clipboard.panel?.frame.contains(point) == true
    let insideSearch = searchPanel.panel?.frame.contains(point) == true
    let insideOptions = optionsPanel.panel?.frame.contains(point) == true
    if insideCourier || insidePreview || insideClipboard || insideSearch || insideOptions {
      recordActivity()
    } else { dismiss() }
  }
  private func clampAnchor() {
    guard let anchor = topRight,
      let frame = placementScreen ?? panel?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
    topRight = CGPoint(x: min(max(anchor.x, frame.minX + physicalCourierSize.width + 8), frame.maxX - 8),
      y: min(max(anchor.y, frame.minY + physicalCourierSize.height + 8), frame.maxY - 8))
  }
  private func resizeKeepingAnchor() {
    if moving { pendingMoveLayout = true; return }
    guard let panel else { return }
    let target = arrangement.frame
    let screen = placementScreen ?? panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? target
    if visible, expanded, showingFolder, !showingBin, !mediaEditor, !confirmingAction,
      let item = filePreview.item, let pair = CourierPreviewLayout.placement(shelf: target, screen: screen,
        desired: CGSize(width: 360 * interfaceScale, height: 320 * interfaceScale), preferRight: side != .left) {
      if panel.frame != pair.shelf { panel.setFrame(pair.shelf, display: true) }
      sidePreview.show(item, frame: pair.preview, scale: interfaceScale, parent: panel,
        hover: { [weak self] inside in
          self?.filePreview.previewHover(inside)
          if inside { self?.recordActivity() }
        }, activity: { [weak self] in self?.recordActivity() }, close: { [weak self] in self?.closeFilePreview() })
    } else {
      filePreview.previewHover(false)
      sidePreview.hide()
      if panel.frame != target { panel.setFrame(target, display: true) }
    }
  }
  func closeFilePreview() {
    filePreview.clear()
    sidePreview.hide()
    if !moving, let panel, panel.frame != arrangement.frame { panel.setFrame(arrangement.frame, display: true) }
  }
  private func ensurePanel(store: ParcelStore) {
    guard panel == nil else { return }
    let panel = ShelfPanel(contentRect: .zero, styleMask: [.borderless],
                           backing: .buffered, defer: false)
    panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
    panel.isFloatingPanel = true
    panel.becomesKeyOnlyIfNeeded = false
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isRestorable = false
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    let host = CourierHostingView(rootView: AnyView(DropPopupView(shelf: self).environmentObject(store)))
    host.pointerChanged = { [weak self] in self?.trackPointer() }
    host.keyHandler = { [weak self] event in self?.handleCourierKey(event) == true }
    host.sizingOptions = []
    panel.contentView = host
    self.host = host
    self.panel = panel
    for (name, active) in [(NSMenu.didBeginTrackingNotification, true), (NSMenu.didEndTrackingNotification, false)] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
        guard let menu = notification.object as? NSMenu else { return }
        MainActor.assumeIsolated { self?.menuTrackingChanged(menu, active: active) }
      })
    }
  }
}

struct DropPopupView: View {
  @ObservedObject var shelf: DropPopupController
  var skin: ParcelSkin? = nil
  var solidSurface = false
  var strongBorder = false
  @EnvironmentObject private var store: ParcelStore
  @StateObject private var skins = SkinStore.shared
  @ObservedObject private var notchTools = NotchToolStore.shared
  @ObservedObject private var notchWidgets = NotchWidgetStore.shared
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast
  @State private var deleteCandidate: ParcelBox?
  @State private var hoveredFile: ParcelItem?
  @State private var draggingFile: ParcelItem?
  private var filePreview: CourierHoverPreview { shelf.filePreview }
  @State private var confirmBinRemoval = false
  @State private var removingFromBin: UUID?
  private var focused: ParcelBox? { store.boxes.first { $0.id == shelf.focusedBox } }
  private var locked: Bool { store.busy || shelf.receiving || store.phase == .receiving }
  private var activeSkin: ParcelSkin { skin ?? skins.skin }
  private var palette: SkinPalette { activeSkin.palette }
  private var showsPaneSurface: Bool {
    shelf.parkedInMenuBar || shelf.showingBin || shelf.mediaEditor || shelf.toolsVisible || deleteCandidate != nil
      || (shelf.showingFolder && shelf.viewStyle != .dial)
  }
  private var ambientSymbol: String {
    if notchTools.timerEnd != nil { return "timer" }
    if notchTools.mediaIsPlaying || notchTools.isPlaying { return "waveform" }
    return "sparkles.rectangle.stack"
  }
  private var ambientTitle: String {
    if notchTools.timerEnd != nil {
      return String(format: "%d:%02d", Int(notchTools.remaining) / 60, Int(notchTools.remaining) % 60)
    }
    if notchTools.mediaIsPlaying { return notchTools.mediaTitle }
    if notchTools.isPlaying { return notchTools.audioTitle }
    return "Skippy"
  }

  var body: some View {
    let layout = shelf.logicalArrangement
    ZStack(alignment: .topLeading) {
      if let pane = layout.pane {
        ZStack {
          Color.clear.contentShape(Rectangle()).onTapGesture(count: 2, perform: shelf.openMainApp)
            .accessibilityLabel("Open Skippy settings")
          Group {
          if shelf.toolsVisible { NotchToolsView(shelf: shelf, skin: activeSkin) }
          else if shelf.showingBin { bin }
          else if let candidate = deleteCandidate { confirmation(candidate) }
          else if shelf.mediaEditor { MediaPreparationView(close: { shelf.mediaEditor = false }) }
          else if shelf.showingFolder, let focused {
            if shelf.viewStyle == .dial {
              CourierDialView(shelf: shelf, box: focused, skin: activeSkin, delete: { deleteCandidate = focused }).id(focused.id)
            } else { folder(focused) }
          }
          else { choices }
          }
        }
        .id(shelf.toolsVisible ? "tools-\(shelf.activeModule.rawValue)" :
          (shelf.showingBin ? "bin" : (shelf.mediaEditor ? "media" : (shelf.showingFolder ? "folder" : "choices"))))
        .modifier(CourierUnfold(order: 0))
        .frame(width: pane.width, height: pane.height)
        .background {
          if showsPaneSurface {
            ZStack {
              if reduceTransparency || solidSurface { palette.paper }
              else { CourierGlass(); palette.paper.opacity(activeSkin == .night ? 0.58 : 0.35) }
            }.clipShape(ParcelNotchShape(attachedToMenuBar: shelf.parkedInMenuBar && shelf.quiverAnchor == nil))
          }
        }
        .overlay {
          if showsPaneSurface {
            ParcelNotchShape(attachedToMenuBar: shelf.parkedInMenuBar && shelf.quiverAnchor == nil)
              .stroke(palette.line, lineWidth: strongBorder || contrast == .increased ? 2 : 0.8)
          }
        }
        .position(x: pane.midX, y: layout.frame.height - pane.midY)
        .transition(.opacity.combined(with: .offset(x: layout.side == .left ? 8 : -8)))
      }
      if !layout.courier.isEmpty {
        courier.frame(width: layout.courier.width, height: layout.courier.height)
          .position(x: layout.courier.midX, y: layout.frame.height - layout.courier.midY)
      }
    }
    .frame(width: layout.frame.width, height: layout.frame.height)
    .scaleEffect(shelf.interfaceScale, anchor: .topLeading)
    .frame(width: shelf.arrangement.frame.width, height: shelf.arrangement.frame.height, alignment: .topLeading)
    .foregroundStyle(palette.text).preferredColorScheme(activeSkin == .night ? .dark : .light)
    .onHover { shelf.hoverChanged($0) }
    .onChange(of: shelf.contentSize) { _, _ in shelf.fitContents() }
    .onChange(of: shelf.side) { _, _ in shelf.fitContents() }
    .onChange(of: shelf.focusedBox) { _, _ in hoveredFile = nil; draggingFile = nil; filePreview.clear() }
    .onChange(of: store.error) { _, error in
      if shelf.expanded, let error { shelf.feedback(error, isError: true); store.error = nil }
    }
    .onChange(of: store.notice) { _, notice in
      if shelf.expanded, let notice { shelf.feedback(notice) }
    }
    .onChange(of: store.searchText) { _, _ in shelf.recordActivity() }
    .onChange(of: shelf.expanded) { _, expanded in
      if !expanded { deleteCandidate = nil; confirmBinRemoval = false; removingFromBin = nil; hoveredFile = nil; draggingFile = nil; filePreview.clear() }
    }
    .onChange(of: shelf.showingBin) { _, showing in
      if showing { shelf.closeFilePreview() }
      if !showing { confirmBinRemoval = false; removingFromBin = nil }
    }
    .onChange(of: shelf.mediaEditor) { _, showing in if showing { shelf.closeFilePreview() } }
    .onChange(of: shelf.toolsVisible) { _, showing in if showing { shelf.closeFilePreview() } }
    .onChange(of: deleteCandidate?.id) { _, _ in shelf.confirmationChanged(deleteCandidate != nil || confirmBinRemoval) }
    .onChange(of: confirmBinRemoval) { _, _ in shelf.confirmationChanged(deleteCandidate != nil || confirmBinRemoval) }
  }
  @ViewBuilder private var courier: some View {
    if !shelf.parkedInMenuBar {
    VStack(spacing: 0) {
      HStack(spacing: 2) {
        Color.clear.frame(width: shelf.expandControlSize, height: shelf.expandControlSize)
        Capsule().fill(palette.secondary.opacity(0.7)).frame(width: 18, height: 2)
          .frame(maxWidth: .infinity, minHeight: max(shelf.closeControlSize, shelf.expandControlSize)).contentShape(Rectangle())
          .overlay(CourierMoveHandle(move: shelf.movePopup(with:)))
        Button(action: shelf.parkInMenuBar) { Image(systemName: "xmark") }
          .buttonStyle(CourierControlStyle(size: shelf.closeControlSize))
          .help("Park courier in the menu bar").accessibilityLabel("Park courier in menu bar")
      }.disabled(locked).frame(height: max(shelf.closeControlSize, shelf.expandControlSize))
        .opacity(shelf.controlsVisible ? 1 : 0).allowsHitTesting(shelf.controlsVisible)
        .accessibilityHidden(!shelf.controlsVisible)
        .animation(Motion.hoverLift, value: shelf.controlsVisible)
        .shadow(color: activeSkin == .night ? .black : .white, radius: 1)
      CourierSatchel(sealed: store.ready && store.selectedBox == shelf.primaryBox?.id,
        count: shelf.primaryBox?.items.count ?? 0,
        awake: shelf.courierHovered || shelf.expanded || shelf.incoming, celebration: shelf.reveal, skin: activeSkin,
        open: shelf.showingFolder && shelf.focusedBox == shelf.primaryBox?.id,
        packingProgress: store.phase == .packing && store.selectedBox == shelf.primaryBox?.id ? store.progress : nil,
        intakeEvent: shelf.intakeBox == shelf.primaryBox?.id ? shelf.intakeEvent : 0, intakeCount: shelf.intakeCount)
        .frame(width: shelf.iconSize, height: shelf.iconSize).allowsHitTesting(false)
        .overlay {
          FileDropSurface(enabled: !locked, tap: shelf.parkedInMenuBar ? shelf.returnFromMenuBar : shelf.tapCourier,
            receive: { _ in }, receiving: { _ in }, hover: shelf.courierHoverChanged, failure: { _ in },
            beginDrop: shelf.beginPrimaryDrop,
            tracksPointer: true, dragHover: shelf.dragHoverChanged,
            doubleTap: shelf.openMainApp, courierMenu: shelf.contextMenu, archiveForDrag: shelf.preparePrimaryArchive)
            .accessibilityLabel("Parcel courier. \(shelf.primaryBox?.isShelfPinned == true ? "Pinned" : "Recent"): \(shelf.primaryBox?.name ?? "New parcel"). Hover for files. Double-click for settings.")
        }
        .overlay(alignment: .bottomLeading) {
          if shelf.primaryBox?.isShelfPinned == true {
            Image(systemName: "pin.fill").font(.system(size: 10, weight: .semibold))
              .padding(5).background(palette.canvas, in: Circle()).allowsHitTesting(false)
          }
        }
      Spacer(minLength: 0)
    }
      .contextMenu {
        Button("Open files", action: shelf.openPrimaryFiles).disabled(locked)
        Button("Open Settings", action: shelf.openMainApp).disabled(locked)
        Button("Courier settings…") { AppController.shared.openPreferences() }
        Button("Quit Skippy") { NSApp.terminate(nil) }
      }
    } else if !shelf.expanded {
      HStack(spacing: 4) {
        HStack(spacing: 6) {
          Image(systemName: ambientSymbol).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.accent)
          Text(ambientTitle).font(.system(size: 9.5, weight: .semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .background {
          ZStack {
            if reduceTransparency || solidSurface { palette.paper }
            else { CourierGlass(); Color.black.opacity(activeSkin == .night ? 0.28 : 0.12) }
          }.clipShape(Capsule())
        }
        .contentShape(Rectangle())
        .overlay {
          FileDropSurface(enabled: !locked, tap: shelf.summon, receive: { _ in }, receiving: { _ in },
            hover: shelf.courierHoverChanged, failure: { _ in }, beginDrop: shelf.beginPrimaryDrop,
            tracksPointer: true, dragHover: shelf.dragHoverChanged, doubleTap: shelf.openMainApp,
            courierMenu: shelf.contextMenu, archiveForDrag: shelf.preparePrimaryArchive)
            .accessibilityLabel("Skippy. Hover to open widgets, or drop files into your parcel.")
        }
        if !notchWidgets.pinned.isEmpty || !notchTools.pinnedApps.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
              ForEach(notchWidgets.pinned) { widget in
                Button { shelf.showModule(widget.kind.module) } label: {
                  Image(systemName: widget.kind.module.symbol).font(.system(size: 9.5, weight: .semibold))
                }.buttonStyle(.plain).frame(width: 25, height: 25).background(palette.paper, in: Circle()).contentShape(Circle())
                  .onHover { if $0 { shelf.showModule(widget.kind.module) } }
                  .foregroundStyle(palette.secondary).help(widget.kind.module.title)
              }
              ForEach(notchTools.pinnedApps) { app in
                Button { notchTools.launch(app) } label: {
                  Image(nsImage: notchTools.icon(for: app)).resizable().frame(width: 17, height: 17)
                }.buttonStyle(.plain).frame(width: 25, height: 25).background(palette.paper, in: Circle()).contentShape(Circle())
                  .help("Open \(app.name)")
              }
            }
          }.frame(width: min(CGFloat(notchWidgets.pinned.count + notchTools.pinnedApps.count) * 29,
            max(25, shelf.arrangement.frame.width - 150)), height: 26)
        }
      }
      .padding(.horizontal, 4).padding(.vertical, 4)
      .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
    }
  }
  private var choices: some View { NotchToolsView(shelf: shelf, skin: activeSkin) }
  private func folder(_ box: ParcelBox) -> some View {
    VStack(spacing: 8) {
      CourierToolbar(shelf: shelf, box: box, skin: activeSkin, hoveredItem: draggingFile ?? hoveredFile,
        delete: { deleteCandidate = box })
      ScrollViewReader { proxy in
        ScrollView {
          CourierFileLayouts(items: store.compactItems(store.filteredItems(in: box)), style: shelf.viewStyle) { item in fileTile(item, box: box) }
          if store.filteredItems(in: box).isEmpty {
            Text(store.isSearching ? "No files match your search." : "Drop files here, or use Paste above.").font(.system(size: 12)).padding(25)
              .frame(maxWidth: .infinity)
          }
        }.frame(maxHeight: .infinity)
          .background {
            FileDropSurface(enabled: !locked, receive: { _ in }, receiving: { _ in }, hover: shelf.hoverChanged,
              failure: { _ in }, beginDrop: { shelf.beginDrop(into: box.id) })
          }
          .onChange(of: shelf.keyboardFocusedItem) { _, item in
            if let item { withAnimation(Motion.layoutRelayout) { proxy.scrollTo(item, anchor: .center) } }
          }
      }
    }.padding(8).onDisappear { filePreview.clear() }
  }
  private func fileTile(_ item: ParcelItem, box: ParcelBox) -> some View {
    let isList = shelf.viewStyle == .list
    let members = store.stackMembers(of: item, in: box)
    let URLs = members.map(\.effectiveURL)
    let selected = members.contains { store.selectedItems.contains($0.id) }
    let layout = isList ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 4))
    return layout {
      layout {
        ZStack(alignment: .bottomTrailing) {
          FileTypeIcon(url: item.effectiveURL, size: isList ? 26 : 34)
          if members.count > 1 {
            Text("\(members.count)").font(.system(size: 7, weight: .bold)).padding(3)
              .background(palette.accent, in: Circle()).foregroundStyle(.white)
          }
        }.frame(width: isList ? 28 : 36, height: isList ? 28 : 36).allowsHitTesting(false)
        Text(item.compactDisplayName).font(.system(size: isList ? 10 : 9)).lineLimit(isList ? 1 : 2)
          .frame(maxWidth: .infinity, minHeight: isList ? 28 : 22, maxHeight: isList ? 28 : 22,
            alignment: isList ? .leading : .center).help(item.effectiveName)
      }.overlay {
        FileDropSurface(enabled: !locked, outgoing: store.canExport ? URLs : [],
          outgoingText: members.count == 1 ? item.inlineText : nil,
          tap: {
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true { store.toggleSelection(item.id) }
            else { shelf.openFile(item) }
          }, receive: { _ in }, receiving: { _ in }, hover: { inside in
            shelf.hoverChanged(inside)
            filePreview.hover(item, inside: inside)
            if inside { hoveredFile = item } else if hoveredFile?.id == item.id { hoveredFile = nil }
          }, failure: { _ in }, beginDrop: { shelf.beginDrop(into: box.id) }, tracksPointer: true,
          courierMenu: { _ in shelf.fileContextMenu(for: item) },
          outgoingDragChanged: { dragging in
            if dragging { draggingFile = item }
            else if draggingFile?.id == item.id { draggingFile = nil }
          })
          .accessibilityLabel("Open or drag \(item.effectiveName)")
      }
    }.padding(3).frame(maxWidth: .infinity)
      .background(hoveredFile?.id == item.id || shelf.keyboardFocusedItem == item.id || selected
        ? palette.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10))
      .contextMenu {
        Button("Open") { shelf.openFile(item) }.disabled(locked)
        Button("Copy file") { shelf.copyFiles(item: item.id) }.disabled(locked || !store.canExport)
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.effectiveURL]) }
      }
  }
  private func confirmation(_ box: ParcelBox) -> some View {
    VStack(spacing: 12) {
      Text("Move ‘\(box.name)’ to Bin?").font(.system(size: 14, weight: .medium)).lineLimit(2)
      Text("Restore within 30 days. Originals stay safe.").font(.system(size: 11))
      HStack {
        Button("Cancel") { deleteCandidate = nil }
        Button("Move to Bin", role: .destructive) { shelf.moveToBin(box.id); deleteCandidate = nil; shelf.showChoices() }
      }.buttonStyle(.bordered)
    }.padding(20)
  }
  private var bin: some View {
    VStack(spacing: 12) {
      HStack { Text("Parcel Bin").font(.headline); Spacer(); Button("Back") { shelf.showingBin = false; shelf.showChoices() } }
      Text("Restore for 30 days. Originals are never deleted.").font(.system(size: 11))
      ScrollView {
        ForEach(store.trashedBoxes) { entry in
          HStack {
            Text(entry.box.name).lineLimit(1); Spacer()
            Button("Restore") { store.restoreFromBin(entry.id) }
            Button {
              removingFromBin = entry.id; confirmBinRemoval = true
            } label: { Image(systemName: "trash") }.accessibilityLabel("Delete \(entry.box.name) permanently")
          }.font(.system(size: 11)).padding(8)
        }
      }
      if confirmBinRemoval {
        Text("Remove permanently? This cannot be undone. Original files stay untouched.").font(.system(size: 11))
        HStack {
          Button("Cancel") { confirmBinRemoval = false }
          Button(removingFromBin == nil ? "Empty Bin" : "Delete permanently", role: .destructive) {
            store.emptyBin(removingFromBin); confirmBinRemoval = false
          }
        }.buttonStyle(.bordered)
      } else {
        Button("Empty Bin…", role: .destructive) { removingFromBin = nil; confirmBinRemoval = true }
          .disabled(store.trashedBoxes.isEmpty)
      }
      Text("Entries expire after 30 days. Only parcel entries are removed.").font(.system(size: 10)).foregroundStyle(palette.secondary)
    }.padding(16).disabled(locked)
  }
}

struct CourierGlass: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active
    return view
  }
  func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

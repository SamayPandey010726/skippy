import AppKit
import Carbon
import Combine
import QuartzCore

import ParcelCore

enum QuiverEmblem: String, CaseIterable {
  case scout = "Scout", spark = "Spark", arrows = "Quiver"
}

/// The same native strip lives in the NSStatusItem or in a floating NSPanel.
/// Keep the primary mark at the outside end when the secondary buttons appear.
@MainActor final class SkippyQuiver: NSObject, ObservableObject {
  static let shared = SkippyQuiver(defaults: .standard, shelf: .shared, widgets: .shared, tools: .shared)
  @Published var surface: QuiverSurface {
    didSet { defaults.set(surface.rawValue, forKey: "skippy.surface"); if installed { attach() } }
  }
  @Published var emblem: QuiverEmblem {
    didSet { defaults.set(emblem.rawValue, forKey: "skippy.emblem"); mark?.emblem = emblem; mark?.needsDisplay = true }
  }
  private(set) var unfolded = false
  private(set) var strip = QuiverStrip()
  private var status: NSStatusItem?
  private var floating: NSPanel?
  private var subscriptions = Set<AnyCancellable>()
  private var foldWork: DispatchWorkItem?
  private var dockHover: DockHover?
  private var dockTile: CGRect?
  private var settingsPresented = false
  private var installed = false
  private var dragging = false
  private var attachmentOrigin: CGRect?
  private var attachmentHint: NSPanel?
  private var handoffPanel: NSPanel?
  private var connectorPanel: NSPanel?
  private let connectorView = QuiverConnectorView()
  private let pinDiameter: CGFloat = 42
  private var activePin: String?
  private var lastPointer: CGPoint?
  private var progress: CGFloat = 0
  private var motion: Timer?
  private var pointerMonitor: Any?
  private var keyboardMonitor: Any?
  private var focusedIndex = 0
  private var previewWork: DispatchWorkItem?
  private var pinPreviewWork: DispatchWorkItem?
  private var satellites: [String: NSPanel] = [:]
  private lazy var quickPins = defaults === UserDefaults.standard ? QuickPinStore.shared : QuickPinStore(defaults: defaults)
  private weak var previewTarget: NSButton?
  private var arrowModules: [NSButton: NotchModule] = [:]
  private var icons: [NSButton] = []
  private var mark: QuiverMark?
  private var center = CGPoint.zero
  private var height: CGFloat = 34
  private var growsRight = false
  private var screenBounds = CGRect.zero
  private let defaults: UserDefaults
  private let shelf: DropPopupController
  private let widgets: NotchWidgetStore
  private let tools: NotchToolStore
  private let cell: CGFloat = 31
  private var display: NSScreen? {
    NSScreen.screens.first { DropPopupController.displayID(for: $0) == defaults.string(forKey: "skippy.display") } ?? NSScreen.main
  }
  init(defaults: UserDefaults, shelf: DropPopupController, widgets: NotchWidgetStore, tools: NotchToolStore) {
    self.defaults = defaults; self.shelf = shelf; self.widgets = widgets; self.tools = tools
    emblem = QuiverEmblem(rawValue: defaults.string(forKey: "skippy.emblem") ?? "") ?? .scout
    surface = QuiverSurface(rawValue: defaults.string(forKey: "skippy.surface") ?? "") ?? .floating
    super.init()
  }

  func install() {
    guard !installed else { return }
    installed = true
    shelf.quiverFloating = { [weak self] in self?.surface == .floating }
    shelf.quiverSideRail = { [weak self] in self?.surface == .left || self?.surface == .right }
    shelf.quiverAnchor = { [weak self] in self?.anchor }
    shelf.quiverObstacles = { [weak self] in
      guard let self else { return [] }
      return self.satellites.values.filter(\.isVisible).map(\.frame) + [self.anchor].compactMap { $0 }
    }
    shelf.arrowGeometryChanged = { [weak self] in self?.showSatellites() }
    shelf.quiverPanelPointer = { [weak self] inside in
      guard let self else { return }
      if inside { self.foldWork?.cancel(); self.foldWork = nil }
      else if !self.stripContainsPointer { self.hover(false) }
    }
    strip.pointer = { [weak self] in self?.hover($0) }
    strip.pointerMoved = { [weak self] in self?.trackArrow(pointerMoved: true) }
    attach()
    quickPins.$pins.combineLatest(quickPins.$alwaysVisible).dropFirst()
      .receive(on: RunLoop.main).sink { [weak self] _ in self?.layout() }.store(in: &subscriptions)
    quickPins.$showConnectors.dropFirst().receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.updateConnectors() }.store(in: &subscriptions)
    NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)
      .sink { [weak self] notification in
        guard let self, let window = notification.object as? NSWindow else { return }
        if window === self.floating || self.satellites.values.contains(where: { $0 === window }) {
          self.updateConnectors()
        }
      }.store(in: &subscriptions)
    SkinStore.shared.$skin.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.layout() }.store(in: &subscriptions)
    widgets.$widgets.combineLatest(tools.$pinnedApps).receive(on: RunLoop.main).sink { [weak self] _ in self?.layout() }.store(in: &subscriptions)
    NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
      .sink { [weak self] _ in
        guard let self, self.keyboardMonitor != nil else { return }
        self.endKeyboardBrowsing(); self.setUnfolded(false)
      }.store(in: &subscriptions)
    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
      .receive(on: RunLoop.main).sink { [weak self] _ in self?.layout() }.store(in: &subscriptions)
  }

  var anchor: CGRect? {
    if let mark, let window = mark.window, window.isVisible {
      return window.convertToScreen(mark.convert(mark.bounds, to: nil))
    }
    if surface == .dock, let dockTile { return dockTile }
    guard let screen = display else { return nil }
    let v = screen.visibleFrame, f = screen.frame
    let x = v.minX > f.minX + 8 ? v.minX : (v.maxX < f.maxX - 8 ? v.maxX : v.midX)
    let y = x == v.midX ? v.minY : v.midY
    return CGRect(x: x, y: y, width: 1, height: 1)
  }

  private func attach() {
    let origin = attachmentOrigin
    attachmentOrigin = nil
    endKeyboardBrowsing()
    foldWork?.cancel(); foldWork = nil; previewWork?.cancel(); pinPreviewWork?.cancel(); motion?.invalidate()
    if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor); self.pointerMonitor = nil }
    unfolded = false; progress = 0
    shelf.dismiss()
    strip.removeFromSuperview()
    if let status { NSStatusBar.system.removeStatusItem(status); self.status = nil }
    floating?.orderOut(nil); floating = nil
    for satellite in satellites.values { satellite.orderOut(nil) }
    connectorPanel?.orderOut(nil)
    activePin = nil
    dockHover?.stop(); dockHover = nil; dockTile = nil
    if surface == .dock {
      NSApp.setActivationPolicy(.regular)
      dockHover = DockHover(entered: { [weak self] tile in
        guard let self, !self.settingsPresented else { return }
        self.dockTile = tile
        self.hover(true); self.layout(); self.floating?.orderFrontRegardless()
      }, left: { [weak self] in self?.hover(false) })
    } else { AppController.shared.restoreAccessoryPolicyIfPossible() }
    if surface == .menu {
      let item = NSStatusBar.system.statusItem(withLength: cell)
      item.button?.addSubview(strip)
      item.button?.setAccessibilityLabel("Skippy quiver")
      status = item
    } else {
      let p = ShelfPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      p.title = "Skippy quiver"; p.level = .statusBar; p.hidesOnDeactivate = false
      p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = surface != .floating; p.isReleasedWhenClosed = false
      p.acceptsMouseMovedEvents = true
      p.contentView = strip; floating = p
    }
    layout()
    if let origin, !settingsPresented, surface == .menu || surface == .dock {
      animateSystemHandoff(from: origin)
    }
    if surface != .dock, !settingsPresented, let panel = floating {
      let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      let destination = panel.frame
      panel.alphaValue = animate && origin == nil ? 0 : 1
      if animate, let origin { panel.setFrame(origin, display: true) }
      panel.orderFrontRegardless()
      let revealAfterLanding = { [weak self, weak panel] in
        guard origin != nil, let self, let panel, self.floating === panel,
          panel.isVisible, self.surface != .floating else { return }
        self.hover(true)
        if !panel.frame.contains(NSEvent.mouseLocation) { self.hover(false) }
        self.updateConnectors()
      }
      if animate {
        NSAnimationContext.runAnimationGroup({ context in
          context.duration = origin == nil ? 0.14 : 0.24
          context.timingFunction = CAMediaTimingFunction(name: .easeOut)
          if origin != nil { panel.animator().setFrame(destination, display: true) }
          panel.animator().alphaValue = 1
        }, completionHandler: {
          MainActor.assumeIsolated { revealAfterLanding() }
        })
      } else {
        revealAfterLanding()
      }
    }
  }

  func suspendForCapture() -> () -> Void {
    let hidden = settingsPresented
    setSettingsPresented(true)
    return { [weak self] in self?.setSettingsPresented(hidden) }
  }

  func setSettingsPresented(_ shown: Bool) {
    settingsPresented = shown
    guard installed else { return }
    if shown {
      endKeyboardBrowsing()
      previewWork?.cancel(); pinPreviewWork?.cancel(); foldWork?.cancel(); foldWork = nil
      setUnfolded(false)
      floating?.orderOut(nil)
      for satellite in satellites.values { satellite.orderOut(nil) }
      connectorPanel?.orderOut(nil)
    } else if surface != .dock {
      floating?.orderFrontRegardless()
      showSatellites()
    }
  }

  func hover(_ inside: Bool) {
    guard !settingsPresented, !dragging, keyboardMonitor == nil else { return }
    if inside {
      lastPointer = NSEvent.mouseLocation
      foldWork?.cancel()
      foldWork = nil
      if !unfolded, defaults.object(forKey: "skippy.hoverLauncher") as? Bool ?? true { setUnfolded(true) }
    } else {
      (previewTarget as? ArrowButton)?.pointing = false
      previewTarget = nil
      previewWork?.cancel()
      scheduleFold()
    }
  }

  private func scheduleFold() {
    guard foldWork == nil else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.foldWork = nil
      let pointer = NSEvent.mouseLocation
      if let frame = self.shelf.presentationFrame, frame.contains(pointer) { return }
      if self.stripContainsPointer { self.trackArrow(); return }
      if self.connectorView.containsPointer(pointer) { self.scheduleFold(); return }
      self.shelf.dismissArrowPreview()
      if self.surface != .floating && self.shelf.arrowSource != nil && self.shelf.presentationFrame != nil { return }
      self.setUnfolded(false)
    }
    foldWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
  }

  private func setUnfolded(_ open: Bool) {
    guard open != unfolded else { return }
    unfolded = open
    if !open { pointerPrimaries = false }
    showSatellites()
    if open {
      // A status item can receive pointer motion through the menu-bar hosting process.
      pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
        MainActor.assumeIsolated { self?.trackArrow(pointerMoved: true) }
      }
    } else if let pointerMonitor {
      NSEvent.removeMonitor(pointerMonitor); self.pointerMonitor = nil
    }
    motion?.invalidate()
    let target: CGFloat = open ? 1 : 0
    let start = progress
    let began = ProcessInfo.processInfo.systemUptime
    let duration = max(0.06, Double(abs(target - start)) * (open ? 0.28 : 0.20))
    func finish() {
      progress = target; render(); motion?.invalidate(); motion = nil
      if !open && surface == .dock { floating?.orderOut(nil) }
    }
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { finish(); return }
    let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
      MainActor.assumeIsolated {
        guard let self else { timer.invalidate(); return }
        let t = min(1, (ProcessInfo.processInfo.systemUptime - began) / duration)
        if t == 1 {
          self.progress = target; self.render(); self.trackArrow(); timer.invalidate(); self.motion = nil
          if !open && self.surface == .dock { self.floating?.orderOut(nil) }
        } else {
          let eased = open ? 1 - pow(1 - t, 3) : t * t * (3 - 2 * t)
          self.progress = start + (target - start) * CGFloat(eased)
          self.render()
        }
      }
    }
    motion = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private var stripContainsPointer: Bool {
    guard let window = strip.window, window.isVisible else { return false }
    let pointer = NSEvent.mouseLocation
    if satellites.values.contains(where: { $0.isVisible && $0.frame.contains(pointer) }) { return true }
    let local = strip.convert(window.convertPoint(fromScreen: pointer), from: nil)
    if surface != .floating { return strip.bounds.contains(local) }
    if satellites.isEmpty && unfolded { return strip.bounds.contains(local) }
    return mark?.frame.contains(local) == true || icons.contains { !$0.isHidden && $0.frame.contains(local) }
  }

  private func trackArrow(pointerMoved: Bool = false) {
    guard unfolded, keyboardMonitor == nil, let window = strip.window else { return }
    let pointer = NSEvent.mouseLocation
    if pointerMoved, pointer != lastPointer {
      lastPointer = pointer
      if !stripContainsPointer, shelf.presentationFrame?.contains(pointer) != true { scheduleFold() }
    }
    let point = strip.convert(window.convertPoint(fromScreen: pointer), from: nil)
    let button = icons.first { !$0.isHidden && $0.isEnabled && $0.frame.contains(point) }
    guard previewTarget !== button else { return }
    previewWork?.cancel()
    (previewTarget as? ArrowButton)?.pointing = false
    (button as? ArrowButton)?.pointing = true
    previewTarget = button
    guard defaults.object(forKey: "skippy.hoverArrowPreviews") as? Bool ?? true,
      let button, let module = arrowModules[button] else { return }
    let work = DispatchWorkItem { [weak self, weak button] in
      guard let self, let button, let window = button.window, self.unfolded else { return }
      let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
      guard rect.contains(NSEvent.mouseLocation) else { return }
      self.shelf.previewArrow(module, at: self.toolAnchor(rect), source: rect)
    }
    previewWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.13, execute: work)
  }

  private func show(_ module: NotchModule, from view: NSView? = nil) {
    let rect = view.flatMap { v in v.window.map { $0.convertToScreen(v.convert(v.bounds, to: nil)) } } ?? anchor
    endKeyboardBrowsing()
    let pin = (view as? QuickPinButton)?.identifier?.rawValue
    shelf.openArrow(module, at: rect.map { pin == nil ? toolAnchor($0) : $0 }, source: rect, pin: pin)
  }

  func toolAnchor(_ button: CGRect) -> CGRect {
    guard let f = floating?.frame, surface == .floating else { return button }
    return CGRect(x: button.minX, y: f.minY, width: button.width, height: f.height)
  }

  func menu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(CourierMenuAction("Open Skippy") { self.show(.dashboard) })
    menu.addItem(CourierMenuAction("Find an arrow…") { self.openArrowFinder() })
    let arrows = NSMenu()
    for module in NotchModule.allCases where module != .dashboard {
      arrows.addItem(CourierMenuAction(module.title) { self.show(module) })
    }
    if !tools.pinnedApps.isEmpty {
      arrows.addItem(.separator())
      for app in tools.pinnedApps { arrows.addItem(CourierMenuAction(app.name) { self.tools.launch(app) }) }
    }
    let all = NSMenuItem(title: "All arrows", action: nil, keyEquivalent: ""); all.submenu = arrows; menu.addItem(all)
    let places = NSMenu()
    for place in QuiverSurface.allCases {
      let item = CourierMenuAction(place.rawValue) {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
          self.defaults.set(DropPopupController.displayID(for: screen), forKey: "skippy.display")
        }
        self.surface = place
      }
      item.state = surface == place ? .on : .off; places.addItem(item)
    }
    let position = NSMenuItem(title: "Attach to", action: nil, keyEquivalent: "")
    position.submenu = places; menu.addItem(position)
    menu.addItem(.separator())
    if surface != .floating {
      menu.addItem(CourierMenuAction("Detach to floating") { self.surface = .floating })
    }
    menu.addItem(CourierMenuAction("Settings…") { AppController.shared.openPreferences() })
    menu.addItem(CourierMenuAction("Quit Skippy") { NSApp.terminate(nil) })
    return menu
  }

  private func layout() {
    guard !dragging, let screen = (dockTile.flatMap { tile in NSScreen.screens.first { $0.frame.intersects(tile) } } ?? display) else { return }
    if surface == .dock && dockTile == nil { return }
    previewWork?.cancel()
    let visible = screen.visibleFrame
    let px = CGFloat(defaults.object(forKey: "skippy.x") as? Double ?? 0.72)
    let py = CGFloat(defaults.object(forKey: "skippy.y") as? Double ?? 0.70)
    center = CGPoint(x: visible.minX + visible.width * px, y: visible.minY + visible.height * py)
    height = surface == .menu ? NSStatusBar.system.thickness : 34
    switch surface {
    case .left: center.x = visible.minX + cell / 2
    case .right: center.x = visible.maxX - cell / 2
    case .top: center.y = visible.maxY - height / 2
    case .bottom: center.y = visible.minY + height / 2
    case .dock:
      if let tile = dockTile {
        center = CGPoint(x: min(max(tile.midX, visible.minX + cell / 2), visible.maxX - cell / 2),
          y: min(max(tile.midY, visible.minY + height / 2), visible.maxY - height / 2))
      }
    case .notch:
      let top = min(visible.maxY, screen.frame.maxY - screen.safeAreaInsets.top)
      center = CGPoint(x: screen.frame.midX, y: top - height / 2)
    default: break
    }
    growsRight = surface != .menu && center.x <= visible.midX
    screenBounds = visible
    center.x = min(max(center.x, visible.minX + cell / 2), visible.maxX - cell / 2)
    center.y = min(max(center.y, screen.frame.minY + height / 2), screen.frame.maxY - height / 2)
    if surface == .floating {
      let radius = QuiverGeometry.wheelRadius + QuiverGeometry.floatingDiameter / 2
      center.x = min(max(center.x, visible.minX + radius), visible.maxX - radius)
      center.y = min(max(center.y, visible.minY + radius), visible.maxY - radius)
    }
    strip.wantsLayer = true
    strip.layer?.masksToBounds = surface != .floating
    strip.layer?.cornerRadius = surface == .menu ? 5 : height / 2
    strip.subviews.forEach { $0.removeFromSuperview() }
    icons.removeAll(); arrowModules.removeAll(); previewTarget = nil
    enum Entry { case tool(NotchModule), app(PinnedNotchApp) }
    let pins = widgets.pinned.map { Entry.tool($0.kind.module) } + tools.pinnedApps.map(Entry.app)
    let direct = quickPins.pins.prefix(3)
    let foregroundPins: [Entry] = direct.compactMap { pin in
      if let module = pin.module { return .tool(module) }
      return tools.pinnedApps.first(where: { $0.id == pin.id }).map(Entry.app)
    }
    let directIDs = Set(direct.map(\.id))
    let remainingPins = pins.filter { entry in
      switch entry {
      case .tool(let module): !directIDs.contains(module.id)
      case .app(let app): !directIDs.contains(app.id)
      }
    }
    let entries = (surface == .floating ? remainingPins : foregroundPins + remainingPins).prefix(3)
    for entry in entries {
      switch entry {
      case .tool(let module):
        let button = strip.addIcon(module.title, image: NSImage(systemSymbolName: module.symbol, accessibilityDescription: nil),
          frame: .zero, inMenu: surface == .menu) { [weak self] view in self?.show(module, from: view) }
        button.toolTip = module.title
        arrowModules[button] = module
        icons.append(button)
      case .app(let app):
        icons.append(strip.addIcon(app.name, image: tools.icon(for: app), frame: .zero, inMenu: surface == .menu) {
          [weak self] _ in self?.tools.launch(app)
        })
      }
    }
    icons.append(strip.addIcon("More arrows", image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil),
      frame: .zero, inMenu: surface == .menu) { [weak self] _ in self?.openArrowFinder() })
    let dark = SkinStore.shared.skin == .night
    let ink = dark ? NSColor(white: 0.94, alpha: 1) : NSColor(calibratedRed: 0.17, green: 0.23, blue: 0.29, alpha: 1)
    let porcelain = NSColor(calibratedRed: 0.958, green: 0.971, blue: 0.989, alpha: 1)
    let background = dark ? NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.22, alpha: 0.97) : porcelain
    for icon in icons {
      icon.contentTintColor = surface == .menu ? .labelColor : ink
      if surface == .floating {
        styleFloatingButton(icon, fill: background, ink: ink, radius: 14)
      }
    }
    strip.layer?.backgroundColor = surface == .menu || surface == .floating ? NSColor.clear.cgColor : background.cgColor
    strip.layer?.borderWidth = surface == .menu || surface == .floating ? 0 : 0.8
    strip.layer?.borderColor = ink.withAlphaComponent(0.18).cgColor
    let mark = QuiverMark(frame: .zero)
    self.mark = mark
    mark.emblem = emblem
    mark.ink = ink
    mark.inMenu = surface == .menu
    if surface == .floating { styleFloatingButton(mark, fill: background, ink: ink, radius: 30) }
    mark.setAccessibilityLabel("Skippy, browse arrows")
    mark.tap = { [weak self] in
      guard let self else { return }
      if self.unfolded || self.surface != .floating || !self.satellites.isEmpty { self.openArrowFinder() }
      else { self.pointerPrimaries = true; self.setUnfolded(true) }
    }
    mark.courierMenu = { [weak self] _ in self?.menu() ?? NSMenu() }
    mark.beginDrop = { [weak self] in self?.shelf.beginPrimaryDrop() }
    mark.dragHover = { [weak self] inside in self?.hover(inside) }
    mark.registerForDraggedTypes([.fileURL, .png, .tiff, .URL, .string] + NSFilePromiseReceiver.readableDraggedTypes.map { .init($0) })
    mark.windowMovement = WindowMoveActions(begin: {}, drag: { [weak self, weak mark] press in
      guard let self, let mark else { return }
      self.dragLauncher(from: mark, press: press)
    }, end: {})
    strip.addSubview(mark)
    render()
    rebuildSatellites()
    if unfolded { trackArrow() }
  }

  private func dragLauncher(from view: QuiverMark, press: NSEvent) {
    guard let window = view.window else { return }
    let start = window.convertToScreen(view.convert(view.bounds, to: nil))
    let grip = window.convertPoint(toScreen: press.locationInWindow)
    let current = NSEvent.mouseLocation
    let badge = movingBadge(at: start.offsetBy(dx: current.x - grip.x, dy: current.y - grip.y))
    dragging = true
    hoverCleanup()
    for satellite in satellites.values { satellite.orderOut(nil) }
    connectorPanel?.orderOut(nil)
    floating?.orderOut(nil)
    badge.orderFrontRegardless()
    var lastSurface = QuiverSurface.floating
    var lastDisplay = ""
    var target: (QuiverSurface, NSScreen)?
    while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
      let point = NSEvent.mouseLocation
      let origin = CGPoint(x: start.minX + point.x - grip.x, y: start.minY + point.y - grip.y)
      badge.setFrameOrigin(origin)
      if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
        let surface = QuiverSurface.snapped(at: point, screen: screen.frame, visible: screen.visibleFrame)
        let display = DropPopupController.displayID(for: screen)
        target = (surface, screen)
        if surface != lastSurface || display != lastDisplay {
          showAttachmentHint(surface, on: screen, at: point)
          if surface != .floating { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
          lastSurface = surface; lastDisplay = display
        }
      }
      if next.type == .leftMouseUp { break }
    }
    dragging = false
    attachmentHint?.orderOut(nil); attachmentHint = nil
    badge.orderOut(nil)
    guard let (surface, screen) = target else {
      floating?.orderFrontRegardless()
      showSatellites()
      return
    }
    let frame = badge.frame, visible = screen.visibleFrame
    defaults.set(DropPopupController.displayID(for: screen), forKey: "skippy.display")
    defaults.set(min(1, max(0, (frame.midX - visible.minX) / visible.width)), forKey: "skippy.x")
    defaults.set(min(1, max(0, (frame.midY - visible.minY) / visible.height)), forKey: "skippy.y")
    attachmentOrigin = frame
    self.surface = surface
  }

  private func hoverCleanup() {
    endKeyboardBrowsing()
    foldWork?.cancel(); foldWork = nil
    previewWork?.cancel()
    pinPreviewWork?.cancel()
    motion?.invalidate()
    shelf.dismissArrowPreview()
  }

  private func movingBadge(at frame: CGRect) -> NSPanel {
    let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .popUpMenu; panel.isOpaque = false; panel.backgroundColor = .clear
    panel.hasShadow = true; panel.ignoresMouseEvents = true; panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    let face = QuiverMark(frame: CGRect(origin: .zero, size: frame.size))
    let dark = SkinStore.shared.skin == .night
    face.emblem = emblem
    face.ink = dark ? NSColor(white: 0.94, alpha: 1) : NSColor(calibratedRed: 0.17, green: 0.23, blue: 0.29, alpha: 1)
    face.wantsLayer = true
    face.layer?.cornerRadius = min(frame.width, frame.height) / 2
    face.layer?.backgroundColor = (dark ? NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.22, alpha: 1)
      : NSColor(calibratedRed: 0.946, green: 0.96, blue: 0.985, alpha: 1)).cgColor
    panel.contentView = face
    return panel
  }

  private func showAttachmentHint(_ target: QuiverSurface, on screen: NSScreen, at pointer: CGPoint) {
    attachmentHint?.orderOut(nil); attachmentHint = nil
    guard target != .floating else { return }
    let visible = screen.visibleFrame
    let side = target == .left || target == .right
    let verticalEdge = side ? (target == .left ? visible.minX + 6 : visible.maxX - 40) : nil
    let size = CGSize(width: side ? 34 : 142, height: side ? 142 : 34)
    let x = verticalEdge ?? min(max(visible.minX + 6, (target == .notch ? visible.midX : pointer.x) - size.width / 2),
      visible.maxX - size.width - 6)
    let y: CGFloat
    if side {
      y = min(max(visible.minY + 6, pointer.y - size.height / 2), visible.maxY - size.height - 6)
    } else if target == .bottom || target == .dock {
      y = visible.minY + 5
    } else {
      y = visible.maxY - size.height - 5
    }
    let panel = NSPanel(contentRect: CGRect(x: x, y: y, width: size.width, height: size.height),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .popUpMenu; panel.isOpaque = false; panel.backgroundColor = .clear
    panel.ignoresMouseEvents = true; panel.isReleasedWhenClosed = false
    let bar = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
    bar.material = .popover; bar.state = .active; bar.wantsLayer = true
    bar.appearance = NSAppearance(named: SkinStore.shared.skin == .night ? .darkAqua : .aqua)
    bar.layer?.cornerRadius = 16; bar.layer?.masksToBounds = true
    bar.layer?.borderColor = NSColor.systemTeal.withAlphaComponent(0.7).cgColor
    bar.layer?.borderWidth = 1.1
    let symbols = ["shippingbox", "rectangle.dashed", "music.note", "ellipsis"]
    for (index, name) in symbols.enumerated() {
      let icon = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage())
      let position = CGFloat(index) * 33 + 12
      icon.frame = CGRect(x: side ? 9 : position, y: side ? position : 9, width: 16, height: 16)
      bar.addSubview(icon)
    }
    panel.title = "Attach Skippy · " + target.rawValue
    panel.contentView = bar
    attachmentHint = panel
    let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    panel.alphaValue = animate ? 0 : 0.92
    panel.orderFrontRegardless()
    if animate {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.13
        panel.animator().alphaValue = 0.92
      }
    }
  }

  private func animateSystemHandoff(from origin: CGRect) {
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
      let target = anchor else { return }
    handoffPanel?.orderOut(nil)
    let badge = movingBadge(at: origin)
    handoffPanel = badge
    badge.orderFrontRegardless()
    let destination = CGRect(x: target.midX - origin.width / 2, y: target.midY - origin.height / 2,
      width: origin.width, height: origin.height)
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.22
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      badge.animator().setFrame(destination, display: true)
      badge.animator().alphaValue = 0
    }, completionHandler: { [weak self, weak badge] in
      MainActor.assumeIsolated {
        badge?.orderOut(nil)
        if self?.handoffPanel === badge { self?.handoffPanel = nil }
      }
    })
  }

  private var floatingPins: [QuickPin] {
    guard surface == .floating else { return [] }
    let pins = Array(quickPins.pins.prefix(3))
    guard !pins.isEmpty else { return [] }
    return pins + [QuickPin(id: NotchModule.dashboard.id, position: .lowerRight, alwaysVisible: false)]
  }

  private func rebuildSatellites() {
    let pins = floatingPins
    let presentable = pins.filter { pin in pin.module != nil || tools.pinnedApps.contains { $0.id == pin.id } }
    let keys = Set(presentable.map(\.id))
    for id in Array(satellites.keys) where !keys.contains(id) {
      satellites.removeValue(forKey: id)?.orderOut(nil)
    }
    var occupied: [CGPoint] = []
    for pin in presentable {
      let app = tools.pinnedApps.first { $0.id == pin.id }
      let more = pin.module == .dashboard
      guard let title = more ? "More arrows" : (pin.module?.title ?? app?.name) else { continue }
      let displayID = display.map(DropPopupController.displayID(for:))
      let offset = displayID.flatMap { pin.displayOffsets?[$0] } ?? pin.position.offset
      let point = pinCenter(CGPoint(x: center.x + offset.x, y: center.y + offset.y), avoiding: occupied)
      occupied.append(point)
      let radius = pinDiameter / 2
      let frame = CGRect(x: point.x - radius, y: point.y - radius, width: pinDiameter, height: pinDiameter)
      if let existing = satellites[pin.id] {
        if existing.frame != frame { existing.setFrame(frame, display: true) }
        applyPinAppearance(existing.contentView as? QuickPinButton, active: pin.id == shelf.arrowSourcePin || pin.id == activePin)
        continue
      }
      let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.level = .statusBar; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
      panel.title = "Skippy pin · " + title
      let button = QuickPinButton(frame: CGRect(origin: .zero, size: frame.size))
      button.identifier = NSUserInterfaceItemIdentifier(pin.id)
      button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
      button.image = pin.module.flatMap { NSImage(systemSymbolName: more ? "ellipsis" : $0.symbol, accessibilityDescription: nil) }
        ?? app.map { tools.icon(for: $0) }
      button.imageScaling = .scaleProportionallyDown
      button.imagePosition = .imageOnly; button.isBordered = false
      button.wantsLayer = true
      button.layer?.cornerRadius = pinDiameter / 2
      applyPinAppearance(button, active: false)
      button.toolTip = title
      button.setAccessibilityLabel(more ? title : title + " quick pin")
      button.setAccessibilityHelp(more ? "Open the Drawer" : "Click to open. Drag around Skippy to reposition.")
      button.target = button; button.action = #selector(QuickPinButton.activatePin)
      button.open = { [weak self, weak button] in
        guard let self else { return }
        self.pinPreviewWork?.cancel()
        if more { self.openArrowFinder(from: button) }
        else if let module = pin.module { self.show(module, from: button) }
        else if let app { self.tools.launch(app) }
      }
      button.hover = { [weak self, weak panel] inside in
        guard let self else { return }
        if inside { self.activePin = pin.id }
        else if self.activePin == pin.id { self.activePin = nil }
        self.updateConnectors()
        self.hover(inside)
        self.pinPreviewWork?.cancel()
        guard inside, !more, self.defaults.object(forKey: "skippy.hoverArrowPreviews") as? Bool ?? true,
          let module = pin.module else { return }
        let work = DispatchWorkItem { [weak self, weak panel] in
          guard let self, let panel, panel.frame.contains(NSEvent.mouseLocation) else { return }
          self.shelf.previewArrow(module, at: panel.frame, source: panel.frame, pin: pin.id)
        }
        self.pinPreviewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13, execute: work)
      }
      button.movePin = more ? nil : { [weak self, weak panel] pointer, finished in
        guard let self, let panel else { return pointer }
        self.pinPreviewWork?.cancel()
        self.foldWork?.cancel(); self.foldWork = nil
        let occupied = self.satellites.compactMap { id, other in
          id == pin.id || id == NotchModule.dashboard.id ? nil : other.frame.centerPoint
        }
        let point = self.pinCenter(pointer, avoiding: occupied)
        let radius = self.pinDiameter / 2
        self.shelf.movePinAnchor(pin.id, to: CGRect(x: point.x - radius, y: point.y - radius,
          width: panel.frame.width, height: panel.frame.height))
        if finished, let screen = self.display {
          self.quickPins.move(pin.id, to: CGPoint(x: point.x - self.center.x, y: point.y - self.center.y),
            on: DropPopupController.displayID(for: screen))
          self.hover(self.stripContainsPointer)
        }
        return point
      }
      panel.contentView = button
      satellites[pin.id] = panel
    }
    showSatellites()
  }

  private func showSatellites() {
    let pins = floatingPins
    let hasPersistentPin = pins.contains(where: quickPins.isAlwaysVisible)
    for pin in pins {
      guard let panel = satellites[pin.id] else { continue }
      let persistent = quickPins.isAlwaysVisible(pin) || pin.module == .dashboard && hasPersistentPin
      if !settingsPresented && !dragging && (unfolded || persistent || shelf.arrowSourcePin == pin.id) {
        if !panel.isVisible {
          let animate = !persistent && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
          panel.alphaValue = animate ? 0 : 1
          panel.orderFrontRegardless()
          if animate {
            NSAnimationContext.runAnimationGroup { context in
              context.duration = 0.19
              panel.animator().alphaValue = 1
            }
          }
        }
      } else if panel.isVisible { panel.orderOut(nil) }
    }
    updateConnectors()
  }

  private func pinCenter(_ point: CGPoint, avoiding occupied: [CGPoint]) -> CGPoint {
    let inset = pinDiameter / 2 + 3
    let bounds = screenBounds.insetBy(dx: inset, dy: inset)
    func clamped(_ point: CGPoint) -> CGPoint {
      CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }
    func clear(_ point: CGPoint) -> Bool {
      hypot(point.x - center.x, point.y - center.y) >= 55 &&
        occupied.allSatisfy { hypot($0.x - point.x, $0.y - point.y) >= pinDiameter + 4 }
    }
    let proposed = clamped(point)
    if clear(proposed) { return proposed }
    let angle = atan2(point.y - center.y, point.x - center.x)
    let nearScout = clamped(CGPoint(x: center.x + 56 * cos(angle), y: center.y + 56 * sin(angle)))
    if clear(nearScout) { return nearScout }
    return QuickPinPosition.allCases.map {
      clamped(CGPoint(x: center.x + $0.offset.x, y: center.y + $0.offset.y))
    }.filter(clear).min {
      hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y)
    } ?? proposed
  }

  private func applyPinAppearance(_ button: QuickPinButton?, active: Bool) {
    let dark = SkinStore.shared.skin == .night
    let bright = NSColor(calibratedRed: 0.60, green: 0.88, blue: 0.88, alpha: 1)
    let fill = dark ? NSColor(calibratedRed: 0.147, green: 0.204, blue: 0.26, alpha: 1)
      : NSColor(calibratedRed: 0.957, green: 0.977, blue: 0.994, alpha: 1)
    let ink = dark ? NSColor(white: 0.93, alpha: 1) : NSColor(calibratedRed: 0.17, green: 0.23, blue: 0.29, alpha: 1)
    button?.layer?.backgroundColor = active ? fill.blended(withFraction: 0.14, of: .systemTeal)?.cgColor : fill.cgColor
    button?.layer?.borderColor = active ? (dark ? bright : .systemTeal).cgColor : ink.withAlphaComponent(0.35).cgColor
    button?.layer?.borderWidth = active ? 1.0 : 0.75
    button?.contentTintColor = active && dark ? bright : ink
  }

  private func updateConnectors() {
    guard !settingsPresented, !dragging, let scout = anchor else {
      connectorView.segments = []
      connectorPanel?.orderOut(nil)
      return
    }
    var segments: [QuiverConnectorView.Segment] = []
    for (id, panel) in satellites where panel.isVisible {
      let active = id == (shelf.arrowSourcePin ?? activePin)
      applyPinAppearance(panel.contentView as? QuickPinButton, active: active)
      segments.append(.init(from: scout.centerPoint, to: panel.frame.centerPoint, active: active))
    }
    if surface == .floating, let window = strip.window {
      for icon in icons where !icon.isHidden && icon.alphaValue > 0.23 {
        let rect = window.convertToScreen(icon.convert(icon.bounds, to: nil))
        segments.append(.init(from: scout.centerPoint, to: rect.centerPoint, active: (icon as? ArrowButton)?.pointing == true))
      }
    }
    if let source = shelf.arrowSource, let card = shelf.presentationFrame {
      let from = (shelf.arrowSourcePin.flatMap { satellites[$0]?.frame } ?? source).centerPoint
      let end = CGPoint(x: min(max(from.x, card.minX + 9), card.maxX - 9),
                        y: min(max(from.y, card.minY + 9), card.maxY - 9))
      segments.append(.init(from: from, to: end, active: true))
    }
    connectorView.segments = segments
    guard quickPins.showConnectors, !segments.isEmpty else {
      connectorPanel?.orderOut(nil)
      return
    }
    let frame = segments.reduce(CGRect.null) { frame, line in
      frame.union(CGRect(x: min(line.from.x, line.to.x), y: min(line.from.y, line.to.y),
        width: max(1, abs(line.from.x - line.to.x)), height: max(1, abs(line.from.y - line.to.y))))
    }.insetBy(dx: -3, dy: -3)
    if connectorPanel == nil {
      let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.title = "Skippy connectors"
      panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
      panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
      panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
      panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
      panel.contentView = connectorView
      connectorPanel = panel
    }
    connectorView.screenOrigin = frame.origin
    if connectorPanel?.frame != frame { connectorPanel?.setFrame(frame, display: false) }
    connectorView.needsDisplay = true
    if connectorPanel?.isVisible == false { connectorPanel?.orderFrontRegardless() }
  }

  func beginKeyboardBrowsing() {
    guard installed else { return }
    if settingsPresented {
      if let window = NSApp.windows.first(where: { $0.title == "Skippy Settings" && $0.isVisible }) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
      }
      return
    }
    if surface == .menu { openArrowFinder(); return }
    foldWork?.cancel(); foldWork = nil
    previewWork?.cancel()
    endKeyboardBrowsing()
    if surface == .dock, dockTile == nil { dockTile = anchor }
    shelf.dismiss()
    layout()
    pointerPrimaries = true
    setUnfolded(true)
    render()
    floating?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    focusIcon(0)
    keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      MainActor.assumeIsolated { self?.handleWheelKey(event) == true ? nil : event }
    }
  }

  private func focusIcon(_ index: Int) {
    guard !icons.isEmpty else { return }
    focusedIndex = (index % icons.count + icons.count) % icons.count
    for (i, button) in icons.enumerated() { (button as? ArrowButton)?.pointing = i == focusedIndex }
    if let floating { floating.makeFirstResponder(icons[focusedIndex]) }
    strip.setAccessibilityHelp(icons[focusedIndex].accessibilityLabel())
  }

  private func handleWheelKey(_ event: NSEvent) -> Bool {
    guard !icons.isEmpty else { endKeyboardBrowsing(); return false }
    switch Int(event.keyCode) {
    case kVK_LeftArrow, kVK_UpArrow: focusIcon(focusedIndex - 1)
    case kVK_RightArrow, kVK_DownArrow: focusIcon(focusedIndex + 1)
    case kVK_Tab: focusIcon(focusedIndex + (event.modifierFlags.contains(.shift) ? -1 : 1))
    case kVK_Escape:
      endKeyboardBrowsing(); setUnfolded(false)
    case kVK_Return, kVK_Space:
      let button = icons[min(focusedIndex, icons.count - 1)]
      endKeyboardBrowsing()
      (button as? ArrowButton)?.openArrow()
    default: return false
    }
    return true
  }

  private func endKeyboardBrowsing() {
    if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor); self.keyboardMonitor = nil }
    strip.setAccessibilityHelp(nil)
  }

  func openArrowFinder(from button: QuickPinButton? = nil) {
    endKeyboardBrowsing()
    previewWork?.cancel()
    let source = button.flatMap { view in view.window?.convertToScreen(view.convert(view.bounds, to: nil)) } ?? anchor
    let pin = button?.identifier?.rawValue
    shelf.openArrow(.dashboard, at: pin == nil ? source.map(toolAnchor) : source, source: source, pin: pin)
    shelf.chooseArrow(fromLauncher: true)
  }

  private var pointerPrimaries = false

  private func styleFloatingButton(_ view: NSView, fill: NSColor, ink: NSColor, radius: CGFloat) {
    view.wantsLayer = true
    view.layer?.cornerRadius = radius
    view.layer?.backgroundColor = fill.cgColor
    view.layer?.borderWidth = 0.7
    view.layer?.borderColor = ink.withAlphaComponent(0.18).cgColor
    view.layer?.shadowColor = NSColor(calibratedRed: 0.12, green: 0.27, blue: 0.43, alpha: 1).cgColor
    view.layer?.shadowOpacity = 0.28
    view.layer?.shadowRadius = 4
    view.layer?.shadowOffset = CGSize(width: 0, height: -2)
  }

  private func render() {
    let geometry = QuiverGeometry(surface: surface, center: center, bounds: screenBounds, count: icons.count,
                                  progress: progress, height: height, growsRight: growsRight)
    if let status, status.length != geometry.frame.width { status.length = geometry.frame.width }
    if let floating, floating.frame != geometry.frame { floating.setFrame(geometry.frame, display: false) }
    strip.frame = CGRect(origin: .zero, size: geometry.frame.size)
    strip.layer?.cornerRadius = surface == .menu ? 5 : min(strip.frame.width, strip.frame.height) / 2
    mark?.frame = geometry.mark
    if surface == .floating { mark?.layer?.shadowOpacity = 0.38 }
    for (i, icon) in icons.enumerated() {
      icon.frame = geometry.buttons[i]
      icon.alphaValue = progress
      let showPrimary = surface != .floating || satellites.isEmpty || keyboardMonitor != nil || pointerPrimaries
      icon.isHidden = progress == 0 || !showPrimary
      icon.isEnabled = showPrimary && unfolded && progress > 0.68
    }
    updateConnectors()
  }
}

@MainActor final class QuiverStrip: NSView {
  var pointer: ((Bool) -> Void)?
  var pointerMoved: (() -> Void)?
  private var tracking: NSTrackingArea?
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited], owner: self)
    addTrackingArea(area); tracking = area
  }
  override func mouseEntered(with event: NSEvent) { pointer?(true); pointerMoved?() }
  override func mouseMoved(with event: NSEvent) { pointerMoved?() }
  override func mouseExited(with event: NSEvent) { pointer?(false) }
  func addIcon(_ title: String, image: NSImage?, frame: CGRect, inMenu: Bool, action: @escaping (NSView) -> Void) -> ArrowButton {
    let button = ArrowButton(frame: frame)
    button.onHover = { [weak self] in self?.pointerMoved?() }
    button.actionHandler = action; button.image = image
    button.imagePosition = .imageOnly; button.isBordered = false; button.bezelStyle = .accessoryBarAction
    button.contentTintColor = inMenu ? .labelColor : .white
    button.imageScaling = .scaleProportionallyDown
    button.toolTip = title; button.setAccessibilityLabel(title)
    button.target = button; button.action = #selector(ArrowButton.openArrow)
    addSubview(button); return button
  }
}

final class ArrowButton: NSButton {
  var onHover: (() -> Void)?
  private var tracking: NSTrackingArea?
  var pointing = false { didSet { if oldValue != pointing { needsDisplay = true } } }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited], owner: self)
    addTrackingArea(area); tracking = area
  }
  override func mouseEntered(with event: NSEvent) { onHover?() }
  override func mouseMoved(with event: NSEvent) { onHover?() }
  override func mouseExited(with event: NSEvent) { onHover?() }
  override func draw(_ dirtyRect: NSRect) {
    if pointing && isEnabled {
      (contentTintColor ?? .labelColor).withAlphaComponent(0.18).setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6).fill()
    }
    super.draw(dirtyRect)
  }

  var actionHandler: ((NSView) -> Void)?
  @objc func openArrow() { actionHandler?(self) }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class QuiverMark: FileDropSurface.ReceivingView {
  var inMenu = false
  var emblem: QuiverEmblem = .scout
  var ink = NSColor.labelColor
  override func draw(_ dirtyRect: NSRect) {
    let color = inMenu ? NSColor.labelColor : ink
    if emblem == .scout {
      let scale = min(1.4, bounds.width / 31)
      let body = CGRect(x: bounds.midX - 10 * scale, y: bounds.midY - 8 * scale, width: 20 * scale, height: 15 * scale)
      color.setFill(); NSBezierPath(roundedRect: body, xRadius: 6 * scale, yRadius: 6 * scale).fill()
      let antenna = NSBezierPath(); antenna.move(to: CGPoint(x: body.midX, y: body.maxY-1))
      antenna.line(to: CGPoint(x: body.midX + 3 * scale, y: body.maxY + 3 * scale)); color.setStroke(); antenna.lineWidth = 1.5; antenna.stroke()
      (inMenu ? NSColor.windowBackgroundColor : (SkinStore.shared.skin == .night ? NSColor.black : NSColor.white)).setFill()
      for dx: CGFloat in [-4, 4] {
        NSBezierPath(roundedRect: CGRect(x: body.midX + (dx - 1.4) * scale, y: body.midY - 2 * scale, width: 2.8 * scale, height: 5 * scale), xRadius: 1.4, yRadius: 1.4).fill()
      }
      return
    }
    if emblem == .spark {
      let path = NSBezierPath()
      for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4
        let radius: CGFloat = i.isMultiple(of: 2) ? 10 : 3.6
        let pt = CGPoint(x: bounds.midX + radius * cos(a), y: bounds.midY + radius * sin(a))
        if i == 0 { path.move(to: pt) } else { path.line(to: pt) }
      }
      path.close(); color.setFill(); path.fill(); return
    }
    color.setFill()
    let x = bounds.midX - 10, y = bounds.midY - 8
    for (dx, dy, length) in [(0.0, 7.0, 8.0), (2.0, 1.0, 13.0)] {
      let p = NSBezierPath()
      p.move(to: CGPoint(x: x + dx, y: y + dy))
      p.line(to: CGPoint(x: x + dx + length, y: y + dy + length))
      p.line(to: CGPoint(x: x + dx + length + 5, y: y + dy + length))
      p.line(to: CGPoint(x: x + dx + 5, y: y + dy))
      p.close(); p.fill()
    }
  }
}

private extension CGRect {
  var centerPoint: CGPoint { CGPoint(x: midX, y: midY) }
}

private final class QuiverConnectorView: NSView {
  struct Segment {
    let from: CGPoint
    let to: CGPoint
    let active: Bool
  }

  var segments: [Segment] = []
  var screenOrigin = CGPoint.zero

  func containsPointer(_ pointer: CGPoint) -> Bool {
    segments.contains { segment in
      let dx = segment.to.x - segment.from.x, dy = segment.to.y - segment.from.y
      let lengthSquared = dx * dx + dy * dy
      guard lengthSquared > 0 else { return false }
      let t = ((pointer.x - segment.from.x) * dx + (pointer.y - segment.from.y) * dy) / lengthSquared
      guard t >= 0, t <= 1 else { return false }
      return hypot(pointer.x - segment.from.x - t * dx, pointer.y - segment.from.y - t * dy) <= 9
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    for segment in segments {
      let path = NSBezierPath()
      path.move(to: CGPoint(x: segment.from.x - screenOrigin.x, y: segment.from.y - screenOrigin.y))
      path.line(to: CGPoint(x: segment.to.x - screenOrigin.x, y: segment.to.y - screenOrigin.y))
      path.lineWidth = segment.active ? 1.25 : 0.85
      let ink = segment.active ? NSColor(calibratedRed: 0.59, green: 0.90, blue: 0.89, alpha: 0.94)
        : NSColor(calibratedRed: 0.62, green: 0.75, blue: 0.83, alpha: 0.78)
      ink.setStroke()
      path.stroke()
    }
  }
}

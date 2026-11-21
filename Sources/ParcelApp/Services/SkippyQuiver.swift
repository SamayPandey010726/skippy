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
    shelf.quiverAnchor = { [weak self] in self?.anchor }
    shelf.quiverPanelPointer = { [weak self] inside in
      guard let self else { return }
      if inside { self.foldWork?.cancel() }
      else if !self.stripContainsPointer { self.hover(false) }
    }
    strip.pointer = { [weak self] in self?.hover($0) }
    strip.pointerMoved = { [weak self] in self?.trackArrow() }
    attach()
    quickPins.$pins.combineLatest(quickPins.$alwaysVisible).dropFirst()
      .receive(on: RunLoop.main).sink { [weak self] _ in self?.layout() }.store(in: &subscriptions)
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
    foldWork?.cancel(); previewWork?.cancel(); motion?.invalidate()
    if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor); self.pointerMonitor = nil }
    unfolded = false; progress = 0
    shelf.dismiss()
    strip.removeFromSuperview()
    if let status { NSStatusBar.system.removeStatusItem(status); self.status = nil }
    floating?.orderOut(nil); floating = nil
    for satellite in satellites.values { satellite.orderOut(nil) }
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
      }
      if animate {
        NSAnimationContext.runAnimationGroup({ context in
          context.duration = origin == nil ? 0.14 : 0.24
          context.timingFunction = CAMediaTimingFunction(name: .easeOut)
          panel.animator().setFrame(destination, display: true)
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
      previewWork?.cancel(); foldWork?.cancel()
      setUnfolded(false)
      floating?.orderOut(nil)
      for satellite in satellites.values { satellite.orderOut(nil) }
    } else if surface != .dock {
      floating?.orderFrontRegardless()
      showSatellites()
    }
  }

  func hover(_ inside: Bool) {
    guard !settingsPresented, !dragging, keyboardMonitor == nil else { return }
    foldWork?.cancel()
    if inside {
      if !unfolded, defaults.object(forKey: "skippy.hoverLauncher") as? Bool ?? true { setUnfolded(true) }
    } else {
      (previewTarget as? ArrowButton)?.pointing = false
      previewTarget = nil; previewWork?.cancel()
      let work = DispatchWorkItem { [weak self] in
        guard let self else { return }
        if self.stripContainsPointer { self.trackArrow(); return }
        if let frame = self.shelf.presentationFrame, frame.contains(NSEvent.mouseLocation) {
          return
        }
        self.shelf.dismissArrowPreview()
        self.setUnfolded(false)
      }
      foldWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
    }
  }

  private func setUnfolded(_ open: Bool) {
    guard open != unfolded else { return }
    unfolded = open
    if !open { pointerPrimaries = false }
    showSatellites()
    if open {
      // A status item can receive pointer motion through the menu-bar hosting process.
      pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
        MainActor.assumeIsolated { self?.trackArrow() }
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
    return satellites.values.contains { $0.isVisible && $0.frame.contains(pointer) }
      || strip.bounds.contains(strip.convert(window.convertPoint(fromScreen: pointer), from: nil))
  }

  private func trackArrow() {
    guard unfolded, keyboardMonitor == nil, let window = strip.window else { return }
    let point = strip.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
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
      self.shelf.previewArrow(module, at: self.toolAnchor(rect))
    }
    previewWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.23, execute: work)
  }

  private func show(_ module: NotchModule, from view: NSView? = nil) {
    let rect = view.flatMap { v in v.window.map { $0.convertToScreen(v.convert(v.bounds, to: nil)) } } ?? anchor
    endKeyboardBrowsing()
    // A satellite owns its own anchor. Promoting its preview must keep that same origin.
    shelf.openArrow(module, at: view is QuickPinButton ? rect : rect.map(toolAnchor))
  }

  func toolAnchor(_ button: CGRect) -> CGRect {
    guard let f = floating?.frame else { return button }
    if surface == .left || surface == .right { return f }
    guard surface == .floating else { return button }
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
    case .notch: center = CGPoint(x: screen.frame.midX, y: screen.frame.maxY - screen.safeAreaInsets.top - height / 2)
    default: break
    }
    growsRight = surface != .menu && center.x <= visible.midX
    screenBounds = visible
    center.x = min(max(center.x, visible.minX + cell / 2), visible.maxX - cell / 2)
    center.y = min(max(center.y, screen.frame.minY + height / 2), screen.frame.maxY - height / 2)
    if surface == .floating {
      center.x = min(max(center.x, visible.minX + 73), visible.maxX - 73)
      center.y = min(max(center.y, visible.minY + 73), visible.maxY - 73)
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
    if surface == .floating { styleFloatingButton(mark, fill: background, ink: ink, radius: 21) }
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
    if surface != .dock {
      mark.windowMovement = WindowMoveActions(begin: {}, drag: { [weak self, weak mark] press in
        guard let self, let mark else { return }
        self.dragLauncher(from: mark, press: press)
      }, end: {})
    }
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
    foldWork?.cancel()
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
    face.emblem = emblem; face.ink = NSColor(calibratedRed: 0.17, green: 0.23, blue: 0.29, alpha: 1)
    face.wantsLayer = true; face.layer?.cornerRadius = 14
    face.layer?.backgroundColor = NSColor(calibratedRed: 0.946, green: 0.96, blue: 0.985, alpha: 0.98).cgColor
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

  private func rebuildSatellites() {
    let pins = surface == .floating ? Array(quickPins.pins.prefix(3)) : []
    let presentable = pins.filter { pin in pin.module != nil || tools.pinnedApps.contains { $0.id == pin.id } }
    let keys = Set(presentable.map(\.id))
    for id in Array(satellites.keys) where !keys.contains(id) {
      satellites.removeValue(forKey: id)?.orderOut(nil)
    }
    for pin in presentable {
      let app = tools.pinnedApps.first { $0.id == pin.id }
      guard let title = pin.module?.title ?? app?.name else { continue }
      let offset = pin.position.offset
      let x = min(max(screenBounds.minX + 14, center.x + offset.x), screenBounds.maxX - 14)
      let y = min(max(screenBounds.minY + 14, center.y + offset.y), screenBounds.maxY - 14)
      let frame = CGRect(x: x - 14, y: y - 14, width: 28, height: 28)
      if let existing = satellites[pin.id] {
        if existing.frame != frame {
          if existing.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
              context.duration = 0.19
              context.timingFunction = CAMediaTimingFunction(name: .easeOut)
              existing.animator().setFrame(frame, display: true)
            }
          } else { existing.setFrame(frame, display: false) }
        }
        continue
      }
      let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.level = .statusBar; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
      panel.title = "Skippy pin · " + title
      let button = QuickPinButton(frame: CGRect(origin: .zero, size: frame.size))
      button.image = pin.module.flatMap { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) }
        ?? app.map { tools.icon(for: $0) }
      button.imageScaling = .scaleProportionallyDown
      button.imagePosition = .imageOnly; button.isBordered = false
      button.contentTintColor = NSColor(calibratedRed: 0.17, green: 0.23, blue: 0.29, alpha: 1); button.wantsLayer = true
      button.layer?.cornerRadius = 14
      button.layer?.backgroundColor = NSColor(calibratedRed: 0.97, green: 0.98, blue: 1.0, alpha: 1).cgColor
      button.layer?.borderColor = NSColor(calibratedRed: 0.55, green: 0.66, blue: 0.74, alpha: 0.6).cgColor
      button.layer?.borderWidth = 0.7
      button.toolTip = title
      button.setAccessibilityLabel(title + " quick pin")
      button.setAccessibilityHelp("Click to open. Drag around Skippy to reposition.")
      button.target = button; button.action = #selector(QuickPinButton.activatePin)
      button.open = { [weak self, weak button] in
        guard let self else { return }
        self.pinPreviewWork?.cancel()
        if let module = pin.module { self.show(module, from: button) }
        else if let app { self.tools.launch(app) }
      }
      button.hover = { [weak self, weak panel, weak button] inside in
        guard let self else { return }
        button?.layer?.borderWidth = inside ? 1.5 : 0.7
        button?.layer?.borderColor = inside ? NSColor.systemTeal.cgColor
          : NSColor(calibratedRed: 0.55, green: 0.66, blue: 0.74, alpha: 0.6).cgColor
        self.hover(inside)
        self.pinPreviewWork?.cancel()
        guard inside, self.defaults.object(forKey: "skippy.hoverArrowPreviews") as? Bool ?? true,
          let module = pin.module else { return }
        let work = DispatchWorkItem { [weak self, weak panel] in
          guard let self, let panel, panel.frame.contains(NSEvent.mouseLocation) else { return }
          self.shelf.previewArrow(module, at: panel.frame)
        }
        self.pinPreviewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: work)
      }
      button.movePin = { [weak self] pointer in
        guard let self else { return }
        let center = self.center
        func distance(_ slot: QuickPinPosition) -> CGFloat {
          hypot(center.x + slot.offset.x - pointer.x, center.y + slot.offset.y - pointer.y)
        }
        if let slot = QuickPinPosition.allCases.min(by: { distance($0) < distance($1) }) {
          self.quickPins.position(pin.id, at: slot)
        }
      }
      panel.contentView = button
      satellites[pin.id] = panel
    }
    showSatellites()
  }

  private func showSatellites() {
    for pin in quickPins.pins.prefix(3) {
      guard let panel = satellites[pin.id] else { continue }
      if !settingsPresented && (unfolded || quickPins.isAlwaysVisible(pin)) {
        if !panel.isVisible {
          let animate = !quickPins.isAlwaysVisible(pin) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
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
    foldWork?.cancel()
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

  func openArrowFinder() {
    endKeyboardBrowsing()
    previewWork?.cancel()
    shelf.openArrow(.dashboard, at: anchor.map(toolAnchor))
    shelf.chooseArrow()
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

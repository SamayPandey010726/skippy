import AppKit
import Carbon
import Combine

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
  private(set) var page = 0
  private(set) var pageCount = 1
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
  private var progress: CGFloat = 0
  private var motion: Timer?
  private var pointerMonitor: Any?
  private var keyboardMonitor: Any?
  private var focusedIndex = 0
  private var previewWork: DispatchWorkItem?
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
    shelf.quiverAnchor = { [weak self] in self?.anchor }
    shelf.quiverPanelPointer = { [weak self] inside in
      guard let self else { return }
      if inside { self.foldWork?.cancel() }
      else if !self.stripContainsPointer { self.hover(false) }
    }
    strip.pointer = { [weak self] in self?.hover($0) }
    strip.pointerMoved = { [weak self] in self?.trackArrow() }
    attach()
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
    endKeyboardBrowsing()
    foldWork?.cancel(); previewWork?.cancel(); motion?.invalidate()
    if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor); self.pointerMonitor = nil }
    unfolded = false; progress = 0; page = 0
    shelf.dismiss()
    strip.removeFromSuperview()
    if let status { NSStatusBar.system.removeStatusItem(status); self.status = nil }
    floating?.orderOut(nil); floating = nil
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
      p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.isReleasedWhenClosed = false
      p.acceptsMouseMovedEvents = true
      p.contentView = strip; floating = p
    }
    layout()
    if surface != .dock, !settingsPresented, let panel = floating {
      let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      panel.alphaValue = animate ? 0 : 1
      panel.orderFrontRegardless()
      if animate {
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.14
          panel.animator().alphaValue = 1
        }
      }
    }
  }

  func setSettingsPresented(_ shown: Bool) {
    settingsPresented = shown
    guard installed else { return }
    if shown {
      endKeyboardBrowsing()
      previewWork?.cancel(); foldWork?.cancel()
      setUnfolded(false)
      floating?.orderOut(nil)
    } else if surface != .dock {
      floating?.orderFrontRegardless()
    }
  }

  func hover(_ inside: Bool) {
    guard !settingsPresented, !dragging, keyboardMonitor == nil else { return }
    foldWork?.cancel()
    if inside {
      if !unfolded { setUnfolded(true) }
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
    let duration = max(0.06, Double(abs(target - start)) * (open ? 0.22 : 0.17))
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
          let eased = t * t * (3 - 2 * t)
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
    return strip.bounds.contains(strip.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
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
    guard let button, let module = arrowModules[button] else { return }
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
    shelf.openArrow(module, at: rect.map(toolAnchor))
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
    let arrows = NSMenu()
    for widget in widgets.widgets {
      arrows.addItem(CourierMenuAction(widget.kind.module.title) { self.show(widget.kind.module) })
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
      center.x = min(max(center.x, visible.minX + 67), visible.maxX - 67)
      center.y = min(max(center.y, visible.minY + 68), visible.maxY - 68)
    }
    strip.wantsLayer = true
    strip.layer?.masksToBounds = true
    strip.layer?.cornerRadius = surface == .menu ? 5 : height / 2
    strip.subviews.forEach { $0.removeFromSuperview() }
    icons.removeAll(); arrowModules.removeAll(); previewTarget = nil
    enum Entry { case tool(NotchWidget), app(PinnedNotchApp) }
    let pins = widgets.pinned.map(Entry.tool) + tools.pinnedApps.map(Entry.app)
    let other = Array(pins.dropFirst(6)) + widgets.widgets.filter { !$0.pinned }.map(Entry.tool)
    pageCount = 1 + (other.count + 5) / 6
    page = min(page, pageCount - 1)
    let entries = page == 0 ? Array(pins.prefix(6)) : Array(other.dropFirst((page-1)*6).prefix(6))
    for entry in entries {
      switch entry {
      case .tool(let widget):
        let module = widget.kind.module
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
    if pageCount > 1 {
      let last = page == pageCount - 1
      icons.append(strip.addIcon(last ? "Back to pins" : "More arrows",
        image: NSImage(systemSymbolName: last ? "arrow.uturn.backward" : "ellipsis", accessibilityDescription: nil),
        frame: .zero, inMenu: surface == .menu) { [weak self] _ in self?.nextPage() })
    }
    let dark = SkinStore.shared.skin == .night
    let ink = dark ? NSColor(white: 0.94, alpha: 1) : NSColor(calibratedRed: 0.15, green: 0.23, blue: 0.21, alpha: 1)
    for icon in icons {
      icon.contentTintColor = surface == .menu ? .labelColor : ink
      if surface == .floating {
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 15
        icon.layer?.backgroundColor = ink.withAlphaComponent(0.085).cgColor
      }
    }
    strip.layer?.backgroundColor = surface == .menu ? NSColor.clear.cgColor :
      (dark ? NSColor(calibratedRed: 0.095, green: 0.12, blue: 0.135, alpha: 0.97) : NSColor(calibratedRed: 0.97, green: 0.975, blue: 0.945, alpha: 0.98)).cgColor
    strip.layer?.borderWidth = surface == .menu ? 0 : 0.8
    strip.layer?.borderColor = ink.withAlphaComponent(0.18).cgColor
    let mark = QuiverMark(frame: .zero)
    self.mark = mark
    mark.emblem = emblem
    mark.ink = ink
    mark.inMenu = surface == .menu
    mark.setAccessibilityLabel(page == 0 ? "Skippy, browse arrows" : "Back to pinned arrows")
    mark.tap = { [weak self] in
      guard let self else { return }
      if self.page != 0 { self.page = 0; self.layout() }
      else { self.nextPage() }
    }
    mark.courierMenu = { [weak self] _ in self?.menu() ?? NSMenu() }
    mark.beginDrop = { [weak self] in self?.shelf.beginPrimaryDrop() }
    mark.dragHover = { [weak self] inside in self?.hover(inside) }
    mark.registerForDraggedTypes([.fileURL, .png, .tiff, .URL, .string] + NSFilePromiseReceiver.readableDraggedTypes.map { .init($0) })
    if let floating, surface != .dock {
      mark.windowMovement = WindowMoveActions(begin: {}, drag: { [weak self] event in
        guard let self else { return }
        self.dragging = true; self.foldWork?.cancel()
        floating.performDrag(with: event)
        self.dragging = false
        let p = NSEvent.mouseLocation
        guard let dest = NSScreen.screens.first(where: { $0.frame.contains(p) }) else { return }
        let v = dest.visibleFrame
        self.defaults.set(DropPopupController.displayID(for: dest), forKey: "skippy.display")
        self.defaults.set(min(1, max(0, (p.x - v.minX) / v.width)), forKey: "skippy.x")
        self.defaults.set(min(1, max(0, (p.y - v.minY) / v.height)), forKey: "skippy.y")
        self.surface = QuiverSurface.snapped(at: p, screen: dest.frame, visible: v)
      }, end: {})
    }
    strip.addSubview(mark)
    render()
    if unfolded { trackArrow() }
  }

  func beginKeyboardBrowsing() {
    foldWork?.cancel()
    previewWork?.cancel()
    endKeyboardBrowsing()
    if surface == .dock, dockTile == nil { dockTile = anchor }
    shelf.dismiss()
    page = 0
    layout()
    setUnfolded(true)
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
      if pageCount > 1 && button === icons.last {
        nextPage(); focusIcon(0)
      } else {
        endKeyboardBrowsing()
        (button as? ArrowButton)?.openArrow()
      }
    default: return false
    }
    return true
  }

  private func endKeyboardBrowsing() {
    if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor); self.keyboardMonitor = nil }
    strip.setAccessibilityHelp(nil)
  }

  func nextPage() {
    shelf.dismiss()
    if !unfolded { setUnfolded(true) }
    page = (page + 1) % pageCount
    layout()
  }

  private func render() {
    let geometry = QuiverGeometry(surface: surface, center: center, bounds: screenBounds, count: icons.count,
                                  progress: progress, height: height, growsRight: growsRight)
    if let status, status.length != geometry.frame.width { status.length = geometry.frame.width }
    if let floating, floating.frame != geometry.frame { floating.setFrame(geometry.frame, display: false) }
    strip.frame = CGRect(origin: .zero, size: geometry.frame.size)
    strip.layer?.cornerRadius = surface == .menu ? 5 : min(strip.frame.width, strip.frame.height) / 2
    mark?.frame = geometry.mark
    for (i, icon) in icons.enumerated() {
      icon.frame = geometry.buttons[i]
      icon.alphaValue = progress
      icon.isHidden = progress == 0
      icon.isEnabled = progress > 0.9
    }
    if progress == 0 && !unfolded && page != 0 { page = 0; layout() }
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
      let body = CGRect(x: bounds.midX - 10, y: bounds.midY - 8, width: 20, height: 15)
      color.setFill(); NSBezierPath(roundedRect: body, xRadius: 6, yRadius: 6).fill()
      let antenna = NSBezierPath(); antenna.move(to: CGPoint(x: body.midX, y: body.maxY-1))
      antenna.line(to: CGPoint(x: body.midX+3, y: body.maxY+3)); color.setStroke(); antenna.lineWidth = 1.5; antenna.stroke()
      (inMenu ? NSColor.windowBackgroundColor : (SkinStore.shared.skin == .night ? NSColor.black : NSColor.white)).setFill()
      for dx: CGFloat in [-4, 4] {
        NSBezierPath(roundedRect: CGRect(x: body.midX + dx - 1.4, y: body.midY-2, width: 2.8, height: 5), xRadius: 1.4, yRadius: 1.4).fill()
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

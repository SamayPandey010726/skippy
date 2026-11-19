import AppKit
import Combine

enum QuiverSurface: String, CaseIterable, Identifiable {
  case menu = "Menu bar", notch = "Notch", floating = "Floating", left = "Left edge"
  case right = "Right edge", top = "Top edge", bottom = "Bottom edge", dock = "Dock"
  var id: Self { self }

  static func snapped(at point: CGPoint, screen: CGRect, visible: CGRect) -> Self {
    if point.y >= visible.maxY - 12 {
      if abs(point.x - screen.midX) < 75 { return .notch }
      if point.x >= screen.maxX - 100 { return .menu }
      return .top
    }
    if point.x < visible.minX + 16 { return .left }
    if point.x > visible.maxX - 16 { return .right }
    if point.y < visible.minY + 16 { return .bottom }
    return .floating
  }

  static func panel(at anchor: CGRect, within bounds: CGRect, size: CGSize) -> CGRect {
    let w = min(size.width, bounds.width), h = min(size.height, bounds.height)
    let below = anchor.minY - h - 3
    let y = below >= bounds.minY ? below : anchor.maxY + 3
    return CGRect(x: min(max(anchor.midX - w / 2, bounds.minX), bounds.maxX - w),
      y: min(max(y, bounds.minY), bounds.maxY - h), width: w, height: h)
  }
}

/// The same native strip lives in the NSStatusItem or in a floating NSPanel.
/// Keep the primary mark at the outside end when the secondary buttons appear.
@MainActor final class SkippyQuiver: NSObject, ObservableObject {
  static let shared = SkippyQuiver(defaults: .standard, shelf: .shared, widgets: .shared, tools: .shared)
  @Published var surface: QuiverSurface {
    didSet { defaults.set(surface.rawValue, forKey: "skippy.surface"); if installed { attach() } }
  }
  private(set) var unfolded = false
  private(set) var strip = QuiverStrip()
  private var status: NSStatusItem?
  private var floating: NSPanel?
  private var subscriptions = Set<AnyCancellable>()
  private var foldWork: DispatchWorkItem?
  private var installed = false
  private var dragging = false
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
    surface = QuiverSurface(rawValue: defaults.string(forKey: "skippy.surface") ?? "") ?? .menu
    super.init()
  }

  func install() {
    guard !installed else { return }
    installed = true
    shelf.quiverAnchor = { [weak self] in self?.anchor }
    strip.pointer = { [weak self] in self?.hover($0) }
    attach()
    widgets.$widgets.combineLatest(tools.$pinnedApps).receive(on: RunLoop.main).sink { [weak self] _ in self?.layout() }.store(in: &subscriptions)
    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
      .receive(on: RunLoop.main).sink { [weak self] _ in self?.layout() }.store(in: &subscriptions)
  }

  var anchor: CGRect? {
    if let mark = strip.subviews.last, let window = mark.window, window.isVisible {
      return window.convertToScreen(mark.convert(mark.bounds, to: nil))
    }
    guard let screen = display else { return nil }
    let v = screen.visibleFrame, f = screen.frame
    let x = v.minX > f.minX + 8 ? v.minX : (v.maxX < f.maxX - 8 ? v.maxX : v.midX)
    let y = x == v.midX ? v.minY : v.midY
    return CGRect(x: x, y: y, width: 1, height: 1)
  }

  private func attach() {
    foldWork?.cancel(); unfolded = false
    shelf.dismiss()
    strip.removeFromSuperview()
    if let status { NSStatusBar.system.removeStatusItem(status); self.status = nil }
    floating?.orderOut(nil); floating = nil
    if surface == .dock { NSApp.setActivationPolicy(.regular); return }
    AppController.shared.restoreAccessoryPolicyIfPossible()
    if surface == .menu {
      let item = NSStatusBar.system.statusItem(withLength: cell)
      item.button?.addSubview(strip)
      item.button?.setAccessibilityLabel("Skippy quiver")
      status = item
    } else {
      let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      p.title = "Skippy quiver"; p.level = .statusBar; p.hidesOnDeactivate = false
      p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.isReleasedWhenClosed = false
      p.contentView = strip; floating = p
    }
    layout()
    floating?.orderFrontRegardless()
  }

  func hover(_ inside: Bool) {
    guard !dragging else { return }
    foldWork?.cancel()
    if inside {
      if !unfolded { unfolded = true; layout(animate: true) }
    } else {
      let work = DispatchWorkItem { [weak self] in
        guard let self else { return }
        if let frame = self.shelf.presentationFrame, frame.insetBy(dx: -5, dy: -5).contains(NSEvent.mouseLocation) {
          self.hover(false); return
        }
        self.unfolded = false; self.layout(animate: true)
      }
      foldWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }
  }

  private func show(_ module: NotchModule, from view: NSView? = nil) {
    let rect = view.flatMap { v in v.window.map { $0.convertToScreen(v.convert(v.bounds, to: nil)) } } ?? anchor
    shelf.openArrow(module, at: rect)
  }

  func menu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(CourierMenuAction("Open Skippy") { self.show(.dashboard) })
    let arrows = NSMenu()
    for widget in widgets.widgets {
      arrows.addItem(CourierMenuAction(widget.kind.module.title) { self.show(widget.kind.module) })
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

  private func layout(animate: Bool = false) {
    guard surface != .dock, !dragging, let screen = display else { return }
    let oldExpandedWidth = strip.frame.width
    let entries = widgets.pinned.map { widget in
      (widget.kind.module.title, NSImage(systemSymbolName: widget.kind.module.symbol, accessibilityDescription: nil),
       { (v: NSView) in self.show(widget.kind.module, from: v) })
    } + tools.pinnedApps.map { app in
      (app.name, Optional(tools.icon(for: app)), { (_: NSView) in self.tools.launch(app) })
    }
    let visible = screen.visibleFrame
    let px = CGFloat(defaults.object(forKey: "skippy.x") as? Double ?? 0.72)
    let py = CGFloat(defaults.object(forKey: "skippy.y") as? Double ?? 0.70)
    var center = CGPoint(x: visible.minX + visible.width * px, y: visible.minY + visible.height * py)
    let height: CGFloat = surface == .menu ? NSStatusBar.system.thickness : 34
    switch surface {
    case .left: center.x = visible.minX + cell / 2
    case .right: center.x = visible.maxX - cell / 2
    case .top: center.y = visible.maxY - height / 2
    case .bottom: center.y = visible.minY + height / 2
    case .notch: center = CGPoint(x: screen.frame.midX, y: screen.frame.maxY - screen.safeAreaInsets.top - height / 2)
    default: break
    }
    let growsRight = surface != .menu && center.x <= visible.midX
    let more = unfolded && entries.count > 5
    let n = unfolded ? min(entries.count, 5) + (more ? 1 : 0) : 0
    let width = cell * CGFloat(1 + n)
    status?.length = width
    let x = min(max(center.x - cell / 2 - (growsRight ? 0 : width - cell), visible.minX), visible.maxX - width)
    if let floating {
      let frame = CGRect(x: x, y: min(max(center.y - height / 2, screen.frame.minY), screen.frame.maxY - height), width: width, height: height)
      floating.setFrame(frame, display: true)
    }
    strip.frame = CGRect(x: 0, y: 0, width: width, height: height)
    strip.wantsLayer = true
    strip.layer?.cornerRadius = surface == .menu ? 5 : height / 2
    strip.layer?.backgroundColor = surface == .menu ? NSColor.clear.cgColor : NSColor(calibratedRed: 0.09, green: 0.20, blue: 0.16, alpha: 0.97).cgColor
    strip.subviews.forEach { $0.removeFromSuperview() }
    func rect(_ slot: Int) -> CGRect { CGRect(x: cell * CGFloat(growsRight ? slot : n - slot), y: 0, width: cell, height: height) }
    if unfolded {
      for (i, entry) in entries.prefix(5).enumerated() {
        let b = strip.addIcon(entry.0, image: entry.1, frame: rect(i + 1), inMenu: surface == .menu, action: entry.2)
        if animate && oldExpandedWidth < width && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
          let destination = b.frame
          b.frame.origin.x = rect(0).origin.x
          b.alphaValue = 0
          NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            b.animator().setFrameOrigin(destination.origin)
            b.animator().alphaValue = 1
          }
        }
      }
      if more {
        _ = strip.addIcon("More arrows", image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil),
          frame: rect(n), inMenu: surface == .menu) { v in self.menu().popUp(positioning: nil, at: .zero, in: v) }
      }
    }
    let mark = QuiverMark(frame: rect(0))
    mark.inMenu = surface == .menu
    mark.setAccessibilityLabel("Open Skippy"); mark.toolTip = "Skippy · Open quiver"
    mark.tap = { [weak self, weak mark] in self?.show(.dashboard, from: mark) }
    mark.courierMenu = { [weak self] _ in self?.menu() ?? NSMenu() }
    mark.beginDrop = { [weak self] in self?.shelf.beginPrimaryDrop() }
    mark.dragHover = { [weak self] inside in self?.hover(inside) }
    mark.registerForDraggedTypes([.fileURL, .png, .tiff, .URL, .string] + NSFilePromiseReceiver.readableDraggedTypes.map { .init($0) })
    if let floating {
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
  }
}

@MainActor final class QuiverStrip: NSView {
  var pointer: ((Bool) -> Void)?
  private var tracking: NSTrackingArea?
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self)
    addTrackingArea(area); tracking = area
  }
  override func mouseEntered(with event: NSEvent) { pointer?(true) }
  override func mouseExited(with event: NSEvent) { pointer?(false) }
  func addIcon(_ title: String, image: NSImage?, frame: CGRect, inMenu: Bool, action: @escaping (NSView) -> Void) -> NSButton {
    let button = ArrowButton(frame: frame)
    button.actionHandler = action; button.image = image
    button.imagePosition = .imageOnly; button.isBordered = false; button.bezelStyle = .accessoryBarAction
    button.contentTintColor = inMenu ? .labelColor : .white
    button.imageScaling = .scaleProportionallyDown
    button.toolTip = title; button.setAccessibilityLabel(title)
    button.target = button; button.action = #selector(ArrowButton.openArrow)
    addSubview(button); return button
  }
}

private final class ArrowButton: NSButton {
  var actionHandler: ((NSView) -> Void)?
  @objc func openArrow() { actionHandler?(self) }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class QuiverMark: FileDropSurface.ReceivingView {
  var inMenu = false
  override func draw(_ dirtyRect: NSRect) {
    let color = inMenu ? NSColor.labelColor : NSColor(calibratedRed: 0.84, green: 0.94, blue: 0.66, alpha: 1)
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

import AppKit
import ApplicationServices

/// The Dock owns its tiles. Accessibility supplies the actual tile, including a magnified or side Dock.
@MainActor final class DockHover {
  private let entered: (CGRect) -> Void
  private let left: () -> Void
  private var poll: Timer?
  private var previousPoint: CGPoint?
  private var overTile = false
  init(entered: @escaping (CGRect) -> Void, left: @escaping () -> Void) {
    self.entered = entered; self.left = left
    // The Dock can consume mouse movement before AppKit's global monitor sees it.
    // While Dock mode is selected, sample the pointer and probe AX only after a move near the Dock.
    let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.moved() }
    }
    timer.tolerance = 0.03
    RunLoop.main.add(timer, forMode: .common)
    poll = timer
  }
  func stop() { poll?.invalidate(); poll = nil }
  private func moved() {
    let mouse = NSEvent.mouseLocation
    guard mouse != previousPoint else { return }
    previousPoint = mouse
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
      (mouse.y < screen.visibleFrame.minY + 64 || mouse.x < screen.visibleFrame.minX + 64 || mouse.x > screen.visibleFrame.maxX - 64),
      AXIsProcessTrusted(), let rect = Self.tile(at: mouse) else {
      if overTile { overTile = false; left() }; return
    }
    if !overTile { overTile = true; entered(rect) }
  }
  private static func attribute(_ item: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(item, key as CFString, &value) == .success ? value : nil
  }
  private static func tile(at point: CGPoint) -> CGRect? {
    guard let top = NSScreen.screens.first?.frame.maxY,
      let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
    let app = AXUIElementCreateApplication(dock.processIdentifier)
    AXUIElementSetMessagingTimeout(app, 0.15)
    let location = CGPoint(x: point.x, y: top - point.y)
    let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
    func bounds(_ node: AXUIElement) -> CGRect? {
      guard let url = attribute(node, kAXURLAttribute) as? URL,
        url.resolvingSymlinksInPath().standardizedFileURL.path == bundle,
        let pos = attribute(node, kAXPositionAttribute), let dim = attribute(node, kAXSizeAttribute) else { return nil }
      var origin = CGPoint.zero, size = CGSize.zero
      guard AXValueGetValue(pos as! AXValue, .cgPoint, &origin),
        AXValueGetValue(dim as! AXValue, .cgSize, &size),
        CGRect(origin: origin, size: size).contains(location) else { return nil }
      return CGRect(x: origin.x, y: top - origin.y - size.height, width: size.width, height: size.height)
    }
    var hit: AXUIElement?
    if AXUIElementCopyElementAtPosition(app, Float(location.x), Float(location.y), &hit) == .success,
       let hit, let rect = bounds(hit) { return rect }
    // Some Dock versions expose the containing AXList as the hit element.
    let lists = attribute(app, kAXChildrenAttribute) as? [AXUIElement] ?? []
    for list in lists {
      let tiles = attribute(list, kAXChildrenAttribute) as? [AXUIElement] ?? []
      for tile in tiles { if let rect = bounds(tile) { return rect } }
    }
    return nil
  }
}

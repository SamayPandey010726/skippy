import AppKit
import ApplicationServices

/// The Dock owns its tiles. Its public accessibility elements identify the tile under the pointer.
@MainActor final class DockHover {
  private let entered: (CGRect) -> Void
  private let left: () -> Void
  private var monitor: Any?
  private var lastProbe = Date.distantPast
  private var overTile = false
  init(entered: @escaping (CGRect) -> Void, left: @escaping () -> Void) {
    self.entered = entered; self.left = left
    monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
      MainActor.assumeIsolated { self?.moved() }
    }
  }
  func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
  private func moved() {
    guard Date().timeIntervalSince(lastProbe) > 0.05 else { return }
    lastProbe = Date()
    let mouse = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
      (mouse.y < screen.visibleFrame.minY + 64 || mouse.x < screen.visibleFrame.minX + 64 || mouse.x > screen.visibleFrame.maxX - 64),
      AXIsProcessTrusted(), let rect = Self.tile(at: mouse) else {
      if overTile { overTile = false; left() }; return
    }
    if !overTile { overTile = true; entered(rect) }
  }
  private static func tile(at point: CGPoint) -> CGRect? {
    guard let top = NSScreen.screens.first?.frame.maxY,
      let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
    let app = AXUIElementCreateApplication(dock.processIdentifier)
    AXUIElementSetMessagingTimeout(app, 0.15)
    var item: AXUIElement?
    guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(top - point.y), &item) == .success, let item else { return nil }
    func attribute(_ name: String) -> CFTypeRef? {
      var value: CFTypeRef?
      return AXUIElementCopyAttributeValue(item, name as CFString, &value) == .success ? value : nil
    }
    guard let url = attribute(kAXURLAttribute) as? URL,
      url.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL,
      let pos = attribute(kAXPositionAttribute), let dim = attribute(kAXSizeAttribute),
      CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(dim) == AXValueGetTypeID() else { return nil }
    var origin = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(pos as! AXValue, .cgPoint, &origin),
      AXValueGetValue(dim as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(x: origin.x, y: top - origin.y - size.height, width: size.width, height: size.height)
  }
}

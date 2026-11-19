// Run against a freshly launched Menu bar installation on the disposable Mac runner.
import AppKit
import ApplicationServices

let pid = Int32(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)
func attr(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
  var value: CFTypeRef?
  return AXUIElementCopyAttributeValue(e, key as CFString, &value) == .success ? value : nil
}
func rect(_ element: AXUIElement) -> CGRect? {
  guard let pos = attr(element, kAXPositionAttribute), let size = attr(element, kAXSizeAttribute) else { return nil }
  var p = CGPoint.zero, s = CGSize.zero
  guard AXValueGetValue(pos as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
  return CGRect(origin: p, size: s)
}
func windows() -> [[String: Any]] {
  (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [])
    .filter { $0[kCGWindowOwnerPID as String] as? Int32 == pid }
}
func menuFrame() -> CGRect? {
  if let bar = attr(app, kAXExtrasMenuBarAttribute) {
    let children = attr(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? []
    if let item = children.compactMap(rect).first(where: { $0.width > 15 && $0.height < 50 }) { return item }
  }
  return windows().compactMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } }
    .first { $0.minY <= 5 && $0.height >= 18 && $0.height <= 45 && $0.width >= 20 }
}
func move(_ point: CGPoint) {
  CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func waitFor(_ label: String, _ predicate: () -> Bool) {
  for _ in 0..<50 {
    if predicate() { print("PASS", label); return }
    Thread.sleep(forTimeInterval: 0.08)
  }
  print("FAIL", label, "menu", String(describing: menuFrame()), "windows", windows().map {
    [$0[kCGWindowName as String], $0[kCGWindowBounds as String]]
  })
  exit(1)
}
func panel() -> CGRect? {
  windows().first { $0[kCGWindowName as String] as? String == "Skippy · File Shelf" }
    .flatMap { $0[kCGWindowBounds as String] as? NSDictionary }.flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
}
waitFor("real menu-bar item is exposed") { menuFrame() != nil }
let collapsed = menuFrame()!
let mark = CGPoint(x: collapsed.midX, y: collapsed.midY)
move(mark)
waitFor("status item expands on hover") { (menuFrame()?.width ?? 0) > collapsed.width + 62 }
Thread.sleep(forTimeInterval: 0.30)
let expanded = menuFrame()!
move(CGPoint(x: expanded.maxX - 46.5, y: expanded.midY))
waitFor("hovering menu-bar shelf opens it") { panel() != nil }
let content = panel()!
move(CGPoint(x: content.midX, y: content.minY + 24))
Thread.sleep(forTimeInterval: 0.80)
waitFor("menu-bar preview survives pointer handoff") { panel() != nil }
let screenshot = Process()
screenshot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
let region = expanded.union(content).insetBy(dx: -8, dy: -2).intersection(CGDisplayBounds(CGMainDisplayID())).integral
screenshot.arguments = ["-x", "-R\(Int(region.minX)),\(Int(region.minY)),\(Int(region.width)),\(Int(region.height))", "build/recordings/Menu-bar.png"]
try screenshot.run(); screenshot.waitUntilExit()
move(CGPoint(x: 45, y: CGDisplayBounds(CGMainDisplayID()).maxY - 50))
waitFor("leaving both surfaces dismisses preview and releases menu space") {
  panel() == nil && abs((menuFrame()?.width ?? 0) - collapsed.width) <= 1
}

// Hover the launcher at its actual screen or Dock position, then follow its first pin into the shelf.
import AppKit
import ApplicationServices

let pid = Int32(CommandLine.arguments[1])!
let surface = CommandLine.arguments[2]
let display = CGDisplayBounds(CGMainDisplayID())
func wait(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }
func require<T>(_ description: String, _ probe: () -> T?) -> T {
  for _ in 0..<75 {
    if let result = probe() { print("PASS", description); return result }
    wait(0.10)
  }
  print("FAIL", description, surface, windows())
  exit(1)
}
func move(_ p: CGPoint) {
  CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func windows() -> [(String, CGRect)] {
  (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []).compactMap {
    guard $0[kCGWindowOwnerPID as String] as? Int32 == pid, let bounds = $0[kCGWindowBounds as String] as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
    return ($0[kCGWindowName as String] as? String ?? "", rect)
  }
}
func attr(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
  var result: CFTypeRef?
  return AXUIElementCopyAttributeValue(node, key as CFString, &result) == .success ? result : nil
}
func axRect(_ node: AXUIElement) -> CGRect? {
  guard let pos = attr(node, kAXPositionAttribute), let dim = attr(node, kAXSizeAttribute) else { return nil }
  var p = CGPoint.zero, s = CGSize.zero
  guard AXValueGetValue(pos as! AXValue, .cgPoint, &p), AXValueGetValue(dim as! AXValue, .cgSize, &s) else { return nil }
  return CGRect(origin: p, size: s)
}
func dockTile() -> CGRect? {
  guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
  var nodes = [AXUIElementCreateApplication(dock.processIdentifier)]
  var i = 0
  while i < nodes.count && i < 300 {
    let node = nodes[i]; i += 1
    if let url = attr(node, kAXURLAttribute) as? URL, url.lastPathComponent == "Skippy.app" { return axRect(node) }
    nodes += attr(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
  }
  return nil
}
func menu() -> CGRect? {
  guard let extras = attr(AXUIElementCreateApplication(pid), kAXExtrasMenuBarAttribute),
        let children = attr(extras as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
  return children.compactMap(axRect).first { $0.width > 15 && $0.height < 50 }
}
func launcher() -> CGRect? {
  if surface == "Menu bar" { return menu() }
  return windows().first(where: { $0.0 == "Skippy quiver" })?.1
}
let mark: CGRect = require("collapsed attachment exists") { surface == "Dock" ? dockTile() : launcher() }
let temp = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
let recorder = Process(), signal = Pipe()
recorder.standardInput = signal
recorder.executableURL = URL(fileURLWithPath: CommandLine.arguments[4])
let width = min(display.width, display.height * 16 / 9, 920)
let height = width * 9 / 16
let crop = CGRect(x: min(max(0, mark.midX-width/2), display.width-width),
                  y: min(max(0, mark.midY-height/2), display.height-height), width: width, height: height)
recorder.arguments = [temp.path] + [crop.minX, crop.minY, width, height].map { String(Double($0)) } + ["HD"]
try recorder.run()
let _: Bool = require("capture started") { FileManager.default.fileExists(atPath: temp.appendingPathComponent("capture.ready").path) ? true : nil }
let start = Date()
print("Surface", surface, "mark", mark, "display", display)
if surface == "Dock" {
  let pointer = CGPoint(x: mark.midX, y: min(mark.midY, display.maxY-1))
  move(pointer)
  wait(0.7)
  print("Dock tile after reveal", String(describing: dockTile()))
}
wait(1)
let target = surface == "Dock" ? (dockTile() ?? mark) : mark
move(CGPoint(x: target.midX, y: target.midY))
let vertical = ["Left edge", "Right edge"].contains(surface)
let expanded: CGRect = require("pointer unfolds launcher") {
  guard let pane = launcher(), (vertical ? pane.height : pane.width) > 115 else { return nil }
  return pane
}
wait(1)
let full = launcher() ?? expanded
let pin: CGPoint
if vertical {
  let fromTop = abs(mark.midY-full.minY) < abs(mark.midY-full.maxY)
  pin = CGPoint(x: full.midX, y: fromTop ? full.minY+51 : full.maxY-51)
} else {
  let fromLeft = surface != "Menu bar" && (surface == "Dock" ? mark.midX <= display.midX : abs(mark.midX-full.minX) < abs(mark.midX-full.maxX))
  pin = CGPoint(x: fromLeft ? full.minX+46.5 : full.maxX-46.5, y: full.midY)
}
move(pin)
let shelf: CGRect = require("first pinned arrow opens File Shelf") { windows().first { $0.0 == "Skippy · File Shelf" }?.1 }
wait(2)
move(CGPoint(x: shelf.midX, y: shelf.midY))
wait(2)
let _: CGRect = require("shelf stays open across pointer handoff") { windows().first { $0.0 == "Skippy · File Shelf" }?.1 }
let away = CGPoint(x: shelf.midX < display.midX ? display.maxX-30 : 30, y: display.midY)
move(away)
let _: Bool = require("shelf dismisses when pointer leaves") { windows().contains { $0.0 == "Skippy · File Shelf" } ? nil : true }
wait(max(0, 17.2-Date().timeIntervalSince(start)))
try signal.fileHandleForWriting.close()
recorder.waitUntilExit()
exit(recorder.terminationStatus)

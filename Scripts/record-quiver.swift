// Runs against the launched development bundle on a Mac desktop.
// Capture only the small region around Skippy's floating mark.
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum RecordingError: Error { case missingWindow, hoverFailed, panelFailed, captureFailed, foldFailed, focusChanged }
let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let pid = Int(CommandLine.arguments[2])!
func windows() -> [CGRect] {
  let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
  return info.compactMap { entry in
    guard entry[kCGWindowOwnerPID as String] as? Int == pid,
      let b = entry[kCGWindowBounds as String] as? NSDictionary else { return nil }
    return CGRect(dictionaryRepresentation: b as CFDictionary)
  }
}
func pointer(_ point: CGPoint, _ type: CGEventType = .mouseMoved) {
  CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}
// A quiet desktop backdrop keeps the native panels legible on the headless runner.
final class Backdrop: NSView {
  override func draw(_ dirtyRect: NSRect) {
    NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.36, blue: 0.31, alpha: 1),
      NSColor(calibratedRed: 0.57, green: 0.69, blue: 0.56, alpha: 1),
      NSColor(calibratedRed: 0.80, green: 0.83, blue: 0.68, alpha: 1)])?.draw(in: bounds, angle: 35)
  }
}
_ = NSApplication.shared
let background = NSWindow(contentRect: NSScreen.screens[0].frame, styleMask: .borderless, backing: .buffered, defer: false)
background.contentView = Backdrop()
background.ignoresMouseEvents = true
background.level = .normal
background.orderFrontRegardless()
background.displayIfNeeded()
func escape() {
  for down in [true, false] {
    CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)
  }
}
escape()
Thread.sleep(forTimeInterval: 0.5)
let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
let priorApp = NSWorkspace.shared.frontmostApplication
if priorApp?.processIdentifier == pid { _ = finder?.activate(options: [.activateIgnoringOtherApps]) }
Thread.sleep(forTimeInterval: 0.3)
let baselineFocus = NSWorkspace.shared.frontmostApplication?.processIdentifier
guard let baselineFocus, baselineFocus != pid else { throw RecordingError.focusChanged }
let screen = CGDisplayBounds(CGMainDisplayID())
guard let mark = windows().first(where: { (26...42).contains($0.width) && (24...44).contains($0.height) }) else {
  print("Skippy windows:", windows()); throw RecordingError.missingWindow
}
let center = CGPoint(x: mark.midX, y: mark.midY)
let width = min(screen.width, 700), height = min(screen.height, 470)
let region = CGRect(x: min(max(0, mark.midX - width * 0.62), screen.maxX - width),
  y: min(max(0, mark.midY - 52), screen.maxY - height), width: width, height: height).integral
var frame = 0
func capture(_ point: CGPoint) throws {
  guard let image = CGWindowListCreateImage(region, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) else { throw RecordingError.captureFailed }
  let rep = NSBitmapImageRep(cgImage: image)
  // WindowServer omits the hardware cursor. Composite the system cursor at the posted event location.
  let bitmap = NSImage(size: region.size)
  bitmap.lockFocus()
  NSImage(cgImage: image, size: region.size).draw(in: CGRect(origin: .zero, size: region.size))
  let cursor = NSCursor.arrow
  let cp = CGPoint(x: point.x - region.minX - cursor.hotSpot.x,
    y: region.maxY - point.y - cursor.image.size.height + cursor.hotSpot.y)
  cursor.image.draw(at: cp, from: .zero, operation: .sourceOver, fraction: 1)
  bitmap.unlockFocus()
  let data = bitmap.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) } ?? rep
  try data.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(String(format: "frame-%04d.png", frame)))
  frame += 1
}
func pause(_ seconds: Double, at point: CGPoint) throws {
  let count = max(1, Int((seconds * 30).rounded()))
  for _ in 0..<count { let start = Date(); try capture(point); Thread.sleep(forTimeInterval: max(0, (1.0 / 30) - Date().timeIntervalSince(start))) }
}
func glide(_ from: CGPoint, _ to: CGPoint) throws {
  for i in 1...15 {
    let t = Double(i) / 15
    let p = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
    pointer(p); try pause(1.0 / 30, at: p)
  }
}
let away = CGPoint(x: center.x - 140, y: center.y + 65)
pointer(away); try pause(0.65, at: away)
try glide(away, center); try pause(0.7, at: center)
guard let strip = windows().first(where: { $0.width > 75 && $0.height <= 44 }) else {
  print("After hover:", windows()); throw RecordingError.hoverFailed
}
let direction: CGFloat = strip.midX < center.x ? -1 : 1
let shelf = CGPoint(x: center.x + 31 * direction, y: center.y)
try glide(center, shelf)
try pause(0.85, at: shelf)
let previewFrame = frame - 1
try FileManager.default.copyItem(at: out.appendingPathComponent(String(format: "frame-%04d.png", previewFrame)), to: out.appendingPathComponent("File-Shelf.png"))
guard windows().contains(where: { $0.width >= 300 && $0.height >= 160 }) else { print("Preview missing", windows(), "mark", mark, "strip", strip, "pointer", shelf); fflush(stdout); throw RecordingError.panelFailed }
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == baselineFocus else { throw RecordingError.focusChanged }
print("PASS hovering preserved foreground application")
let notes = CGPoint(x: center.x + 93 * direction, y: center.y)
try glide(shelf, notes)
try pause(0.55, at: notes)
pointer(notes, .leftMouseDown); pointer(notes, .leftMouseUp); try pause(0.65, at: notes)
try glide(notes, center)
pointer(center, .leftMouseDown); pointer(center, .leftMouseUp); try pause(1.6, at: center)
escape()
try glide(center, away); try pause(2.45, at: away)
guard windows().contains(where: { $0.width == mark.width && $0.height == mark.height }) else { throw RecordingError.foldFailed }
print("Recorded", frame, "frames from the running Mac app. Collapsed, unfolded, opened tools and folded.")

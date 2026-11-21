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
let recorderApp = NSApplication.shared
recorderApp.setActivationPolicy(.accessory)
recorderApp.finishLaunching()
let background = NSWindow(contentRect: NSScreen.screens[0].frame, styleMask: .borderless, backing: .buffered, defer: false)
background.contentView = Backdrop()
background.ignoresMouseEvents = true
background.level = .floating
background.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
background.orderFrontRegardless()
background.displayIfNeeded()
RunLoop.main.run(until: Date().addingTimeInterval(0.15))
func escape() {
  for down in [true, false] {
    CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)
  }
}
escape()
Thread.sleep(forTimeInterval: 0.5)
// Launch a real editor so that a passive preview has a distinct foreground process to preserve.
let sample = out.appendingPathComponent("Focus check.txt")
try "Skippy focus check".write(to: sample, atomically: true, encoding: .utf8)
let openEditor = Process()
openEditor.executableURL = URL(fileURLWithPath: "/usr/bin/open")
openEditor.arguments = ["-a", "TextEdit", sample.path]
try openEditor.run(); openEditor.waitUntilExit()
for _ in 0..<60 {
  if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit" { break }
  RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
let baselineFocus = NSWorkspace.shared.frontmostApplication?.processIdentifier
guard let baselineFocus, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit" else {
  print("Could not establish editor focus", NSWorkspace.shared.frontmostApplication?.localizedName ?? "none"); fflush(stdout)
  throw RecordingError.focusChanged
}
let screen = CGDisplayBounds(CGMainDisplayID())
guard let mark = windows().first(where: { (26...42).contains($0.width) && (24...44).contains($0.height) }) else {
  print("Skippy windows:", windows()); throw RecordingError.missingWindow
}
let center = CGPoint(x: mark.midX, y: mark.midY)
let width = min(960, screen.width, screen.height * 16 / 9), height = width * 9 / 16
let region = CGRect(x: min(max(0, mark.midX - width * 0.5), screen.maxX - width),
  y: min(max(0, mark.midY - 92), screen.maxY - height), width: width, height: height).integral
let live = Process()
let stop = Pipe()
live.standardInput = stop
live.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("display-recorder")
live.arguments = [out.path] + [region.minX, region.minY, region.width, region.height].map { String(Double($0)) } + ["HD"]
try live.run()
for _ in 0..<100 {
  if FileManager.default.fileExists(atPath: out.appendingPathComponent("capture.ready").path) { break }
  if !live.isRunning { throw RecordingError.captureFailed }
  Thread.sleep(forTimeInterval: 0.05)
}
guard FileManager.default.fileExists(atPath: out.appendingPathComponent("capture.ready").path) else { throw RecordingError.captureFailed }
print("ScreenCaptureKit recording with Reduce Motion =", NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
let captureStart = Date()
func saveShelfImage() throws {
  guard let image = CGWindowListCreateImage(region, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]),
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
    throw RecordingError.captureFailed
  }
  try png.write(to: out.appendingPathComponent("File-Shelf.png"))
}
func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }
func glide(_ from: CGPoint, _ to: CGPoint) throws {
  for i in 1...15 {
    let t = Double(i) / 15
    let p = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
    pointer(p); pause(1.0 / 30)
  }
}
let away = CGPoint(x: center.x - 140, y: center.y + 65)
pointer(away); pause(0.65)
try glide(away, center); pause(0.7)
guard let strip = windows().first(where: { (120...150).contains($0.width) && (120...150).contains($0.height) }) else {
  print("After hover:", windows()); throw RecordingError.hoverFailed
}
let shelf = CGPoint(x: strip.midX, y: strip.midY - 51)
try glide(center, shelf)
for _ in 0..<50 {
  if windows().contains(where: { $0.width >= 300 && $0.height >= 160 }) { break }
  pause(0.1)
}
try saveShelfImage()
guard windows().contains(where: { $0.width >= 300 && $0.height >= 160 }) else { print("Preview missing", windows(), "mark", mark, "strip", strip, "pointer", shelf); fflush(stdout); throw RecordingError.panelFailed }
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == baselineFocus else {
  print("Hover changed focus to", NSWorkspace.shared.frontmostApplication?.localizedName ?? "none"); fflush(stdout)
  throw RecordingError.focusChanged
}
print("PASS hovering preserved foreground application")
let notes = CGPoint(x: strip.midX, y: strip.midY + 51)
try glide(shelf, notes)
pause(0.55)
pointer(notes, .leftMouseDown); pointer(notes, .leftMouseUp); pause(0.65)
try glide(notes, center)
pointer(center, .leftMouseDown); pointer(center, .leftMouseUp); pause(1.2)
guard windows().contains(where: { abs($0.width-strip.width) <= 1 && abs($0.height-strip.height) <= 1 }),
      windows().contains(where: { $0.width >= 300 && $0.height >= 160 }) else {
  throw RecordingError.panelFailed
}
print("PASS Scout opens the searchable arrow list next to the stable wheel")
escape(); pause(0.35); escape()
try glide(center, away); pause(2.45)
guard windows().contains(where: { $0.width == mark.width && $0.height == mark.height }) else { throw RecordingError.foldFailed }
pause(max(0, 17.2 - Date().timeIntervalSince(captureStart)))
try stop.fileHandleForWriting.close()
live.waitUntilExit()
guard live.terminationStatus == 0 else { throw RecordingError.captureFailed }
NSRunningApplication(processIdentifier: baselineFocus)?.hide()
print("Recorded the running Mac app with ScreenCaptureKit. Collapsed, unfolded, opened tools and folded.")

// Uses the same global shortcut, keyboard finder and Return action as a person at the Mac.
import AppKit
import Carbon
import CoreGraphics

let pid = Int(CommandLine.arguments[1])!
func key(_ code: Int, flags: CGEventFlags = [], character: Character? = nil) {
  for down in [true, false] {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)!
    event.flags = flags
    if let character {
      let units = Array(String(character).utf16)
      event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
    }
    event.post(tap: .cghidEventTap)
  }
}
func panels() -> [[String: Any]] {
  let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
  return windows.filter { info in
    guard info[kCGWindowOwnerPID as String] as? Int == pid,
          let bounds = info[kCGWindowBounds as String] as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
    return rect.width >= 300 && rect.height >= 160
  }
}
var controlFailures: [String] = []
var checkingControls = false
func check(_ label: String, until predicate: () -> Bool) {
  for _ in 0..<50 {
    if predicate() { print("PASS", label); return }
    Thread.sleep(forTimeInterval: 0.08)
  }
  print("Accessibility tree", descendants().flatMap(labels).prefix(90))
  print("FAIL", label, "visible panel names", panels().map { $0[kCGWindowName as String] ?? "(unnamed)" })
  if checkingControls { controlFailures.append(label) } else { exit(1) }
}
let gallery = URL(fileURLWithPath: "build/recordings/Arrows", isDirectory: true)
try FileManager.default.createDirectory(at: gallery, withIntermediateDirectories: true)
func captureArrow(_ name: String) {
  guard let panel = panels().first(where: { $0[kCGWindowName as String] as? String == "Skippy · " + name }),
        let id = panel[kCGWindowNumber as String] as? UInt32 else { return }
  let capture = Process()
  capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  capture.arguments = ["-x", "-o", "-l", String(id), gallery.appendingPathComponent(name + ".png").path]
  do { try capture.run(); capture.waitUntilExit() } catch { print("Capture failed for", name, error) }
}
let application = AXUIElementCreateApplication(pid_t(pid))
func attribute(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
  var result: CFTypeRef?
  guard AXUIElementCopyAttributeValue(node, key as CFString, &result) == .success else { return nil }
  return result
}
func descendants() -> [AXUIElement] {
  var nodes = attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
  var i = 0
  while i < nodes.count && nodes.count < 600 {
    nodes.append(contentsOf: attribute(nodes[i], kAXChildrenAttribute) as? [AXUIElement] ?? [])
    i += 1
  }
  return nodes
}
func labels(_ node: AXUIElement) -> [String] {
  [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXPlaceholderValueAttribute].compactMap {
    attribute(node, $0) as? String
  }
}
func control(_ role: String, _ label: String? = nil) -> AXUIElement? {
  descendants().first { node in
    attribute(node, kAXRoleAttribute) as? String == role && (label.map { labels(node).contains($0) } ?? true)
  }
}
func contains(_ text: String) -> Bool { descendants().contains { labels($0).contains(text) } }
@discardableResult func press(_ title: String) -> Bool {
  guard let button = control(kAXButtonRole, title) else { return false }
  return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
}
func enter(_ string: String, role: String = kAXTextFieldRole) {
  guard let field = control(role) else { return }
  AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
  Thread.sleep(forTimeInterval: 0.12)
  key(kVK_ANSI_A, flags: .maskCommand)
  Thread.sleep(forTimeInterval: 0.06)
  for c in string { key(c == "/" ? kVK_ANSI_Slash : kVK_ANSI_A, character: c); Thread.sleep(forTimeInterval: 0.01) }
  Thread.sleep(forTimeInterval: 0.2)
}
func mouse(_ type: CGEventType, _ point: CGPoint) {
  CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
  Thread.sleep(forTimeInterval: 0.08)
}
func stroke(from start: CGPoint, to end: CGPoint) {
  mouse(.mouseMoved, start)
  mouse(.leftMouseDown, start)
  for i in 1...6 {
    let t = CGFloat(i) / 6
    mouse(.leftMouseDragged, CGPoint(x: start.x + t * (end.x-start.x), y: start.y + t * (end.y-start.y)))
  }
  mouse(.leftMouseUp, end)
}
func verifyContent(_ name: String) {
  let board = NSPasteboard.general
  switch name {
  case "File Shelf":
    check("files opened into shelf") { contains("Launch notes.txt") }
  case "Extract text":
    let image = NSImage(size: NSSize(width: 420, height: 110))
    image.lockFocus()
    NSColor.white.setFill(); NSBezierPath(rect: CGRect(origin: .zero, size: image.size)).fill()
    ("SKIPPY TEST" as NSString).draw(at: NSPoint(x: 30, y: 32), withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
    image.unlockFocus()
    board.clearContents(); board.writeObjects([image])
    check("run Vision from clipboard") { press("Clipboard") }
    check("OCR writes expected words") { board.string(forType: .string)?.uppercased().contains("SKIPPY TEST") == true }
  case "Pick colour":
    board.clearContents()
    check("open system pixel sampler") { press("Pick a pixel") }
    Thread.sleep(forTimeInterval: 0.65)
    let point = CGPoint(x: 80, y: 180)
    mouse(.mouseMoved, point); mouse(.leftMouseDown, point); mouse(.leftMouseUp, point)
    check("sample actual screen pixel into pasteboard") {
      board.string(forType: .string)?.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil
    }
  case "Timer":
    check("start timer") { press("Start") }
    check("stop active countdown") { press("Stop") }
    check("timer returns to start") { control(kAXButtonRole, "Start") != nil }
  case "Notes":
    enter("Skippy / focus", role: kAXTextAreaRole)
    check("copy edited note") { press("Copy note") }
    check("note contains literal slash") { board.string(forType: .string) == "Skippy / focus" }
  case "Clipboard":
    board.clearContents(); board.setString("Skippy clipboard fixture", forType: .string)
    check("capture clipboard change") { contains("Skippy clipboard fixture") }
    enter("clipboard fixture")
    board.clearContents(); board.setString("temporary value", forType: .string)
    check("recall a filtered clipboard entry") { press("Copy Skippy clipboard fixture") }
    check("clipboard restores the selected contents") { board.string(forType: .string) == "Skippy clipboard fixture" }
  case "QR tools":
    enter("Skippy QA")
    check("copy generated QR") { press("Copy QR") }
    check("pasteboard contains generated image") { NSImage(pasteboard: board) != nil }
  case "Search":
    enter("Skippy native"); check("edit web query") { contains("Skippy native") }
  case "Apps":
    check("list running Finder") { contains("Finder") }
  case "Music":
    check("local playback picker available") { control(kAXButtonRole, "Play a local file") != nil }
  case "Downloads":
    check("recent download fixture") { contains("Skippy QA.txt") }
  case "Stay awake":
    check("acquire sleep assertion") { press("Stay awake") }
    check("release sleep assertion") { press("Allow sleep") }
  case "Recent actions":
    check("recent activity or empty state") { contains("No recent actions") || contains("Launch notes.txt") || descendants().contains { node in
      labels(node).contains { $0.localizedCaseInsensitiveContains("copied") }
    } }
  case "Mac":
    check("read real operating system version") { contains(ProcessInfo.processInfo.operatingSystemVersionString) }
  case "Calendar":
    check("fresh calendar account has a connect action") { control(kAXButtonRole, "Connect") != nil }
  case "Calculator":
    enter("(24 + 8) / 2")
    check("copy calculated result") { press("Copy") }
    check("calculator produced 16") { board.string(forType: .string) == "16" }
  case "Screenshots":
    check("empty capture sequence") { contains("0 regions") }
    check("start screen region capture") { press("Add region") }
    Thread.sleep(forTimeInterval: 0.85)
    stroke(from: CGPoint(x: 80, y: 160), to: CGPoint(x: 180, y: 230))
    check("region appears in sequence") { contains("1 regions") || contains("1 region") }
    check("copy joined regions") { press("Copy joined") }
    check("joined region on pasteboard") { NSImage(pasteboard: board) != nil }
    check("clear capture sequence") { press("Clear") }
  case "Draw on screen":
    check("open drawing overlay") { press("Start drawing") }
    check("drawing toolbar") { control(kAXButtonRole, "Done") != nil }
    stroke(from: CGPoint(x: 120, y: 180), to: CGPoint(x: 210, y: 245))
    check("stroke enables undo") {
      guard let button = control(kAXButtonRole, "Undo") else { return false }
      return attribute(button, kAXEnabledAttribute) as? Bool == true
    }
    check("undo stroke") { press("Undo") }
    check("undo clears last stroke") {
      control(kAXButtonRole, "Undo").flatMap { attribute($0, kAXEnabledAttribute) as? Bool } == false
    }
    check("close drawing overlay") { press("Done") }
  default: break
  }
}

let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
let fixture = downloads.appendingPathComponent("Skippy QA.txt")
try Data("Skippy test fixture".utf8).write(to: fixture, options: .withoutOverwriting)
defer { try? FileManager.default.removeItem(at: fixture) }
check("Accessibility can exercise UI controls") { AXIsProcessTrusted() }
let runningApp = NSRunningApplication(processIdentifier: pid_t(pid))
if !panels().isEmpty {
  _ = runningApp?.activate(options: [.activateIgnoringOtherApps])
  key(kVK_Escape)
  check("clear a previously open tool") { panels().isEmpty }
}
_ = runningApp?.activate(options: [])
Thread.sleep(forTimeInterval: 0.20)
key(kVK_ANSI_P, flags: [.maskControl, .maskAlternate, .maskCommand])
check("global shortcut opens dashboard") {
  panels().contains { $0[kCGWindowName as String] as? String == "Skippy · Skippy" }
}
let arrows = ["File Shelf", "Clipboard", "Extract text", "Pick colour", "Timer", "Notes", "QR tools", "Search",
              "Apps", "Music", "Downloads", "Stay awake", "Recent actions", "Mac", "Calendar", "Calculator", "Screenshots", "Draw on screen"]
for name in arrows {
  // A system sampler or capture tool may still be restoring the prior panel.
  for _ in 0..<12 where panels().isEmpty { Thread.sleep(forTimeInterval: 0.08) }
  if panels().isEmpty {
    controlFailures.append("Tool dismissed unexpectedly before " + name)
    key(kVK_ANSI_P, flags: [.maskControl, .maskAlternate, .maskCommand])
    check("recover dashboard before " + name) { !panels().isEmpty }
  }
  key(kVK_ANSI_K, flags: .maskCommand)
  Thread.sleep(forTimeInterval: 0.35)
  for character in name {
    key(kVK_ANSI_A, character: character)
    Thread.sleep(forTimeInterval: 0.025)
  }
  key(kVK_Return)
  check("open " + name) { panels().contains { $0[kCGWindowName as String] as? String == "Skippy · " + name } }
  Thread.sleep(forTimeInterval: 0.18)
  captureArrow(name)
  checkingControls = true
  verifyContent(name)
  checkingControls = false
}
key(kVK_ANSI_P, flags: [.maskControl, .maskAlternate, .maskCommand])
check("summon again after leaving drawing") { !panels().isEmpty }
key(kVK_Escape)
check("Escape dismisses the final tool") { panels().isEmpty }

if !controlFailures.isEmpty { print("Failed control checks:", controlFailures); exit(1) }

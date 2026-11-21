// Uses the same global shortcut, keyboard finder and Return action as a person at the Mac.
import AppKit
import Carbon
import CoreGraphics

let pid = Int(CommandLine.arguments[1])!
let filming = ProcessInfo.processInfo.environment["SKIPPY_FEATURE_FILMS"] == "1"
func beat(_ seconds: Double) {
  if filming { Thread.sleep(forTimeInterval: seconds) }
}

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
func typeText(_ value: String) {
  let codes = Dictionary(uniqueKeysWithValues: zip(Array("abcdefghijklmnopqrstuvwxyz "), [
    kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H,
    kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P,
    kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
    kVK_ANSI_Y, kVK_ANSI_Z, kVK_Space
  ]))
  for c in value {
    let code = codes[Character(String(c).lowercased())] ?? (c == "/" ? kVK_ANSI_Slash : kVK_ANSI_A)
    key(code, flags: c.isUppercase ? .maskShift : [], character: c)
    Thread.sleep(forTimeInterval: filming ? 0.10 : 0.02)
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
// The source is a live region of the macOS display. Capture begins before the finder opens.
final class FeatureFilm {
  let recorder = Process()
  let signal = Pipe()
  let directory: URL
  let start: Date
  let region: CGRect
  init(_ title: String, about panel: CGRect) throws {
    directory = URL(fileURLWithPath: "build/feature-captures", isDirectory: true)
      .appendingPathComponent(title, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let screen = CGDisplayBounds(CGMainDisplayID())
    let width = min(max(880, (panel.height + 32) * 16 / 9), screen.width, screen.height * 16 / 9)
    let height = width * 9 / 16
    region = CGRect(x: min(max(0, panel.midX - width / 2), screen.width - width),
                    y: min(max(0, panel.midY - height / 2 - 24), screen.height - height),
                    width: width, height: height)
    recorder.executableURL = URL(fileURLWithPath: "build/display-recorder")
    recorder.arguments = [directory.path] + [region.minX, region.minY, region.width, region.height].map { String(Double($0)) } + ["HD"]
    recorder.standardInput = signal
    try recorder.run()
    let ready = directory.appendingPathComponent("capture.ready").path
    for _ in 0..<200 where !FileManager.default.fileExists(atPath: ready) && recorder.isRunning {
      Thread.sleep(forTimeInterval: 0.05)
    }
    guard FileManager.default.fileExists(atPath: ready), recorder.isRunning else { throw CocoaError(.fileWriteUnknown) }
    start = Date()
  }
  func finish() throws {
    Thread.sleep(forTimeInterval: max(0, 17.2 - Date().timeIntervalSince(start)))
    try signal.fileHandleForWriting.close()
    recorder.waitUntilExit()
    guard recorder.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
  }
}
var film: FeatureFilm?
func startFilm(_ title: String) throws {
  guard filming else { return }
  guard let b = panels().first?[kCGWindowBounds as String] as? NSDictionary,
        let pane = CGRect(dictionaryRepresentation: b as CFDictionary) else { throw CocoaError(.fileNoSuchFile) }
  film = try FeatureFilm(title, about: pane)
  beat(0.6)
}
func finishFilm() throws { try film?.finish(); film = nil }
func demonstrationPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
  guard let region = film?.region else { return CGPoint(x: x, y: y) }
  return CGPoint(x: region.minX + x, y: region.minY + y)
}

var controlFailures: [String] = []
var checkingControls = false
func check(_ label: String, attempts: Int = 50, until predicate: () -> Bool) {
  for _ in 0..<attempts {
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
func center(of node: AXUIElement) -> CGPoint? {
  guard let position = attribute(node, kAXPositionAttribute),
        let size = attribute(node, kAXSizeAttribute) else { return nil }
  var p = CGPoint.zero, sz = CGSize.zero
  guard AXValueGetValue(position as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &sz) else { return nil }
  return CGPoint(x: p.x + sz.width / 2, y: p.y + sz.height / 2)
}
@discardableResult func press(_ title: String) -> Bool {
  guard let button = control(kAXButtonRole, title) else { return false }
  if filming, let point = center(of: button) { mouse(.mouseMoved, point); beat(0.75) }
  return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
}
func enter(_ string: String, role: String = kAXTextFieldRole) {
  guard let field = control(role) else { return }
  AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
  Thread.sleep(forTimeInterval: 0.12)
  key(kVK_ANSI_A, flags: .maskCommand)
  Thread.sleep(forTimeInterval: 0.06)
  typeText(string)
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
func returnFromExternalApp() {
  beat(2)
  NSRunningApplication(processIdentifier: pid_t(pid))?.activate(options: [.activateIgnoringOtherApps])
  guard let info = panels().first, let b = info[kCGWindowBounds as String] as? NSDictionary,
        let pane = CGRect(dictionaryRepresentation: b as CFDictionary) else { return }
  let title = CGPoint(x: pane.midX, y: pane.minY + 15)
  mouse(.mouseMoved, title); mouse(.leftMouseDown, title); mouse(.leftMouseUp, title)
}
func verifyContent(_ name: String) {
  let board = NSPasteboard.general
  switch name {
  case "File Shelf":
    check("files opened into shelf") { contains("Launch notes.txt") }
    board.clearContents()
    check("write an existing file URL to the system clipboard") {
      FileManager.default.fileExists(atPath: fixture.path) && board.setString(fixture.absoluteString, forType: .fileURL)
    }
    check("paste a file into Parcels") { press("Paste") }
    check("pasted file appears in the shelf") { contains(fixture.lastPathComponent) }

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
    let point = demonstrationPoint(80, 180)
    mouse(.mouseMoved, point); mouse(.leftMouseDown, point); mouse(.leftMouseUp, point)
    check("sample actual screen pixel into pasteboard") {
      board.string(forType: .string)?.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil
    }
  case "Timer":
    check("start timer") { press("Start") }
    beat(3)
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
    if batch == "searchhandoff" {
      let browser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://www.google.com")!)
      key(kVK_Return)
      let browserID = browser.flatMap { Bundle(url: $0)?.bundleIdentifier }
      check("submitted search opens the registered browser", attempts: 175) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.04))
        guard let browserID, panels().isEmpty else { return false }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == browserID
      }
      print("Search handler:", browserID ?? "unknown", "foreground:", NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")
      returnFromExternalApp()
    }
  case "Apps":
    check("list running Finder") { contains("Finder") }
    check("pin Finder") { press("Pin Finder") }
    check("unpin Finder") { press("Unpin Finder") }
    check("pin state restored") { control(kAXButtonRole, "Pin Finder") != nil }
  case "Music":
    check("local playback picker available") { control(kAXButtonRole, "Play a local file") != nil }
    if let button = control(kAXButtonRole, "Play a local file"), let point = center(of: button) {
      mouse(.mouseMoved, point); mouse(.leftMouseDown, point); mouse(.leftMouseUp, point)
      Thread.sleep(forTimeInterval: 0.7)
      key(kVK_ANSI_G, flags: [.maskCommand, .maskShift])
      Thread.sleep(forTimeInterval: 0.35)
      board.clearContents(); board.setString("/System/Library/Sounds/Glass.aiff", forType: .string)
      key(kVK_ANSI_V, flags: .maskCommand)
      Thread.sleep(forTimeInterval: 0.45); key(kVK_Return)
      check("complete selection of the audio file") {
        if contains("Glass") && !panels().contains(where: { $0[kCGWindowName as String] as? String == "Open" }) { return true }
        guard contains("Glass.aiff"), let button = control(kAXButtonRole, "Open"),
              attribute(button, kAXEnabledAttribute) as? Bool == true else { return false }
        return press("Open")
      }
      check("open system audio in local player") { contains("Glass") }
    }
  case "Downloads":
    check("recent download fixture") { contains("Skippy QA.txt") }
    if batch == "downloadhandoff" {
      check("open the listed download") { press(fixture.lastPathComponent) }
      check("document opens in its registered app") {
        guard let editor = NSWorkspace.shared.frontmostApplication,
              let handler = NSWorkspace.shared.urlForApplication(toOpen: fixture),
              editor.bundleURL?.standardizedFileURL.path == handler.standardizedFileURL.path else { return false }
        let app = AXUIElementCreateApplication(editor.processIdentifier)
        let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        return windows.contains { labels($0).contains(where: { $0.contains("Skippy QA") }) }
      }
      returnFromExternalApp()
    }
  case "Stay awake":
    check("acquire sleep assertion") { press("Stay awake") }
    beat(1.8)
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
    stroke(from: demonstrationPoint(80, 160), to: demonstrationPoint(180, 230))
    check("region appears in sequence") { contains("1 regions") || contains("1 region") }
    check("copy joined regions") { press("Copy joined") }
    check("joined region on pasteboard") { NSImage(pasteboard: board) != nil }
    check("clear capture sequence") { press("Clear") }
  case "Draw on screen":
    check("open drawing overlay") { press("Start drawing") }
    check("drawing toolbar") { control(kAXButtonRole, "Done") != nil }
    stroke(from: demonstrationPoint(120, 180), to: demonstrationPoint(210, 245))
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

func windowFrame(_ title: String) -> CGRect? {
  let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
  return windows.first { $0[kCGWindowOwnerPID as String] as? Int == pid && $0[kCGWindowName as String] as? String == title }
    .flatMap { $0[kCGWindowBounds as String] as? NSDictionary }
    .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
}

func chooseMenu(_ title: String, item: String) -> Bool {
  guard let button = descendants().first(where: { labels($0).contains(title) && ["AXMenuButton", "AXPopUpButton", "AXButton"]
    .contains(attribute($0, kAXRoleAttribute) as? String ?? "") }),
    let position = center(of: button) else { return false }
  mouse(.mouseMoved, position)
  mouse(.leftMouseDown, position)
  mouse(.leftMouseUp, position)
  for _ in 0..<25 {
    if let entry = control(kAXMenuItemRole, item) {
      return AXUIElementPerformAction(entry, kAXPressAction as CFString) == .success
    }
    Thread.sleep(forTimeInterval: 0.08)
  }
  return false
}

func useArrow(_ code: Int, _ name: String) {
  key(code, flags: [.maskControl, .maskAlternate, .maskCommand])
  check("global shortcut opens " + name) { windowFrame("Skippy · " + name) != nil }
}

func captureWorkspaceFilms(using fixture: URL) throws {
  let board = NSPasteboard.general
  if !panels().isEmpty {
    NSRunningApplication(processIdentifier: pid_t(pid))?.activate(options: [.activateIgnoringOtherApps])
    key(kVK_Escape)
  }
  key(kVK_ANSI_S, flags: [.maskCommand, .maskShift])
  check("Command-Shift-S expands Scout from the desktop") { (windowFrame("Skippy quiver")?.width ?? 0) >= 125 }
  key(kVK_Escape)
  check("Escape collapses Scout") { (windowFrame("Skippy quiver")?.width ?? 0) < 45 }

  guard let pin = windowFrame("Skippy pin · Calculator") else {
    throw CocoaError(.fileNoSuchFile)
  }
  mouse(.mouseMoved, CGPoint(x: pin.midX, y: pin.midY))
  check("hovering the Calculator pin opens a preview") { windowFrame("Skippy · Calculator") != nil }
  try startFilm("Calculator hover, click and keyboard")
  mouse(.mouseMoved, CGPoint(x: 15, y: 180))
  check("passive calculator preview closes when the pointer leaves") { windowFrame("Skippy · Calculator") == nil }
  let point = CGPoint(x: pin.midX, y: pin.midY)
  mouse(.mouseMoved, point)
  check("hovering the pin reopens the preview") { windowFrame("Skippy · Calculator") != nil }
  beat(1)
  mouse(.leftMouseDown, point); mouse(.leftMouseUp, point)
  check("calculator focuses its expression on click") {
    guard let focused = attribute(application, kAXFocusedUIElementAttribute),
      CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
    return labels(focused as! AXUIElement).contains("Expression") || labels(focused as! AXUIElement).contains("e.g. (24 + 8) / 2")
  }
  enter("sqrt(81)+2^3")
  check("copy result from scientific expression") { press("Copy") }
  check("scientific expression produces 17") { board.string(forType: .string) == "17" }
  mouse(.mouseMoved, CGPoint(x: 15, y: 180))
  beat(3)
  check("the clicked calculator remains open") { windowFrame("Skippy · Calculator") != nil }
  try finishFilm()

  key(kVK_ANSI_S, flags: .maskCommand)
  check("open standalone Skippy Settings") { windowFrame("Skippy Settings") != nil }
  try startFilm("Workspace Settings")
  check("open Placement settings") { press("Placement") }
  check("display all placements") { contains("Floating") && contains("Notch") && contains("Dock") && contains("Menu bar") }
  check("open Pins settings") { press("Pins") }
  check("show pinned Calculator") { contains("Calculator") }
  check("open Shortcuts settings") { press("Shortcuts") }
  check("show editable launcher hotkey") { contains("Open Skippy shortcut") }
  try finishFilm()
  key(kVK_ANSI_W, flags: .maskCommand)
  check("Settings closes") { windowFrame("Skippy Settings") == nil }

  useArrow(kVK_ANSI_V, "Convert files")
  try startFilm("Convert and compress in Parcels")
  board.clearContents()
  _ = board.writeObjects([fixture as NSURL])
  check("paste text fixture into the converter") { press("Paste files") }
  check("converter shows the filename") { contains(fixture.lastPathComponent) }
  check("convert text to PDF") { press("Convert") }
  check("PDF lands in File Shelf") { contains("Ready in the File Shelf. Originals kept.") }
  check("copy the converted file") { press("Copy result") }
  let pdfs = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
  guard let pdf = pdfs.first, try Data(contentsOf: pdf).starts(with: Data("%PDF".utf8)) else {
    throw CocoaError(.fileReadCorruptFile)
  }
  useArrow(kVK_ANSI_Z, "Compress files")
  check("paste the converted PDF") { press("Paste files") }
  check("compress the PDF to ZIP") { press("Compress") }
  check("ZIP lands in File Shelf") { contains("Ready in the File Shelf. Originals kept.") }
  check("copy the ZIP file URL") { press("Copy result") }
  useArrow(kVK_ANSI_X, "Extract archive")
  check("paste the generated ZIP") { press("Paste files") }
  check("extract the ZIP") { press("Extract") }
  check("extracted folder lands in File Shelf") { contains("Ready in the File Shelf. Originals kept.") }
  check("copy the extracted folder") { press("Copy result") }
  let folders = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
  guard let folder = folders.first, try Data(contentsOf: folder.appendingPathComponent(pdf.lastPathComponent)) == Data(contentsOf: pdf) else {
    throw CocoaError(.fileReadCorruptFile)
  }
  try finishFilm()

  useArrow(kVK_ANSI_B, "Draw on screen")
  try startFilm("Draw and capture four regions")
  check("open real markup canvas") { press("Start drawing") }
  check("show markup controls") { control(kAXButtonRole, "Done") != nil }
  let bounds = CGDisplayBounds(CGMainDisplayID())
  let middle = CGPoint(x: bounds.midX, y: bounds.midY)
  let anchors = [CGPoint(x: middle.x - 210, y: middle.y - 125), CGPoint(x: middle.x + 20, y: middle.y - 125),
    CGPoint(x: middle.x - 210, y: middle.y + 20), CGPoint(x: middle.x + 20, y: middle.y + 20)]
  for corner in anchors {
    stroke(from: CGPoint(x: corner.x + 15, y: corner.y + 25), to: CGPoint(x: corner.x + 100, y: corner.y + 68))
  }
  check("choose Multiple capture from the markup toolbar", attempts: 1) { chooseMenu("Capture", item: "Multiple") }
  check("capture shows the interactive region selector") { windowFrame("Skippy · Select regions") != nil }
  for corner in anchors {
    stroke(from: corner, to: CGPoint(x: corner.x + 180, y: corner.y + 108))
  }
  check("four numbered regions are selected") { contains("Done (4)") }
  check("commit the region selection") { press("Done (4)") }
  check("return to the drawing overlay") { windowFrame("Skippy · Markup canvas") != nil }
  check("close markup without deleting the captures") { press("Done") }
  useArrow(kVK_ANSI_4, "Screenshots")
  check("four annotated screenshots are listed") { contains("4 regions") }
  check("copy the composite PNG") { press("Copy joined") }
  guard let png = board.data(forType: .png), let image = NSBitmapImageRep(data: png), image.pixelsHigh >= 432 else {
    throw CocoaError(.fileReadCorruptFile)
  }
  var markFound = false
  for y in stride(from: 0, to: image.pixelsHigh, by: 2) {
    for x in stride(from: 0, to: image.pixelsWide, by: 2) {
      if let colour = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
        colour.redComponent > 0.76, colour.greenComponent < 0.37, colour.blueComponent < 0.37 {
        markFound = true
        break
      }
    }
    if markFound { break }
  }
  check("the composed pixels contain the drawn red stroke", attempts: 1) { markFound }
  try finishFilm()
}

let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
let fixture = downloads.appendingPathComponent("Skippy QA.txt")
try Data("Skippy test fixture".utf8).write(to: fixture, options: .withoutOverwriting)
defer { try? FileManager.default.removeItem(at: fixture) }
check("Accessibility can exercise UI controls") { AXIsProcessTrusted() }
if ProcessInfo.processInfo.environment["SKIPPY_FILM_BATCH"] == "workspace" {
  try captureWorkspaceFilms(using: fixture)
  exit(0)
}
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
key(kVK_ANSI_K, flags: .maskCommand)
check("finder opens over dashboard") { control(kAXTextFieldRole, "Find an arrow") != nil }
typeText("cal"); key(kVK_DownArrow); key(kVK_Return)
check("Down and Return select the second matching tool") {
  panels().contains { $0[kCGWindowName as String] as? String == "Skippy · Calculator" }
}
key(kVK_ANSI_K, flags: .maskCommand)
check("finder reopens over calculator") { control(kAXTextFieldRole, "Find an arrow") != nil }
key(kVK_ANSI_A, flags: .maskCommand); typeText("zzzz"); check("finder explains an empty result") { contains("No matching arrows") }
key(kVK_Escape)
check("Escape cancels search and preserves the current tool") {
  panels().contains { $0[kCGWindowName as String] as? String == "Skippy · Calculator" } && !contains("No matching arrows")
}
let arrows = ["File Shelf", "Clipboard", "Extract text", "Pick colour", "Timer", "Notes", "QR tools", "Search",
              "Apps", "Music", "Downloads", "Stay awake", "Recent actions", "Mac", "Calendar", "Calculator", "Screenshots", "Draw on screen"]
let batch = ProcessInfo.processInfo.environment["SKIPPY_FILM_BATCH"] ?? "all"
let selected: [String]
switch batch {
case "files": selected = Array(arrows[0..<6]) + ["Convert files", "Compress files", "Extract archive"]
case "utilities": selected = Array(arrows[6..<10])
case "system": selected = Array(arrows[10..<16])
case "capture": selected = Array(arrows[16...])
case "preferences": selected = []
case "searchhandoff": selected = ["Search"]
case "downloadhandoff": selected = ["Downloads"]
default: selected = arrows + ["Convert files", "Compress files", "Extract archive"]
}
for name in selected {
  // A system sampler or capture tool may still be restoring the prior panel.
  for _ in 0..<12 where panels().isEmpty { Thread.sleep(forTimeInterval: 0.08) }
  if panels().isEmpty {
    controlFailures.append("Tool dismissed unexpectedly before " + name)
    key(kVK_ANSI_P, flags: [.maskControl, .maskAlternate, .maskCommand])
    check("recover dashboard before " + name) { !panels().isEmpty }
  }
  try startFilm(name == "QR tools" ? "QR generator" : name)
  key(kVK_ANSI_K, flags: .maskCommand)
  check("finder accepts keyboard focus") {
    guard let value = attribute(application, kAXFocusedUIElementAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
    return labels(value as! AXUIElement).contains("Find an arrow")
  }
  beat(1.3)
  key(kVK_ANSI_A, flags: .maskCommand)
  typeText(name.lowercased())
  beat(0.9)
  key(kVK_Return)
  check("open " + name) { panels().contains { $0[kCGWindowName as String] as? String == "Skippy · " + name } }
  Thread.sleep(forTimeInterval: 0.18)
  captureArrow(name)
  checkingControls = true
  beat(1.5)
  verifyContent(name)
  try finishFilm()
  if name == "QR tools" {
    try startFilm("QR scanner")
    beat(2)
    check("scan the generated QR image from the clipboard") { press("Scan clipboard") }
    check("Vision decodes original payload into the clipboard") { NSPasteboard.general.string(forType: .string) == "Skippy QA" }
    try finishFilm()
  }
  checkingControls = false
}
if filming && (batch == "all" || batch == "preferences") {
  if panels().isEmpty {
    key(kVK_ANSI_P, flags: [.maskControl, .maskAlternate, .maskCommand])
    check("summon launcher for keyboard browsing") { !panels().isEmpty }
  }
  try startFilm("Keyboard and launcher")
  beat(1)
  beat(2)
  key(kVK_ANSI_I, flags: [.maskAlternate, .maskShift])
  beat(1)
  key(kVK_ANSI_B, flags: [.maskAlternate, .maskShift])
  beat(1.2)
  key(kVK_RightArrow); beat(0.8); key(kVK_RightArrow); beat(0.8); key(kVK_Return)
  check("select Notes from the wheel by keyboard") { panels().contains { $0[kCGWindowName as String] as? String == "Skippy · Notes" } }
  try finishFilm()
  key(kVK_ANSI_S, flags: .maskCommand)
  check("Settings is the standalone window") { panels().contains { $0[kCGWindowName as String] as? String == "Skippy Settings" } }
  check("launcher clears the settings controls") {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return !windows.contains { $0[kCGWindowOwnerPID as String] as? Int == pid && $0[kCGWindowName as String] as? String == "Skippy quiver" }
  }
  try startFilm("Settings")
  beat(1.5)
  check("open shortcut settings") { press("Shortcuts") }
  beat(3)
  check("return to General settings") { press("General") }
  try finishFilm()
  key(kVK_ANSI_W, flags: .maskCommand)
  check("closing Settings returns to the mark") { panels().isEmpty }
}
if !panels().isEmpty {
  key(kVK_Escape)
  check("dismiss the current tool") { panels().isEmpty }
}
key(kVK_ANSI_P, flags: [.maskControl, .maskAlternate, .maskCommand])
check("summon again after leaving the tool") { !panels().isEmpty }
key(kVK_Escape)
check("Escape dismisses the final tool") { panels().isEmpty }

if !controlFailures.isEmpty { print("Failed control checks:", controlFailures); exit(1) }

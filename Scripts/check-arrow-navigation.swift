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
func check(_ label: String, until predicate: () -> Bool) {
  for _ in 0..<50 {
    if predicate() { print("PASS", label); return }
    Thread.sleep(forTimeInterval: 0.08)
  }
  print("FAIL", label, "visible panel names", panels().map { $0[kCGWindowName as String] ?? "(unnamed)" })
  exit(1)
}
key(kVK_ANSI_P, flags: [.maskControl, .maskAlternate, .maskCommand])
check("global shortcut opens dashboard") { !panels().isEmpty }
let arrows = ["File Shelf", "Clipboard", "Extract text", "Pick colour", "Timer", "Notes", "QR tools", "Search",
              "Apps", "Music", "Downloads", "Stay awake", "Recent actions", "Mac", "Calendar", "Calculator", "Screenshots", "Draw on screen"]
for name in arrows {
  key(kVK_ANSI_K, flags: .maskCommand)
  Thread.sleep(forTimeInterval: 0.35)
  for character in name {
    key(kVK_ANSI_A, character: character)
    Thread.sleep(forTimeInterval: 0.025)
  }
  key(kVK_Return)
  check("open " + name) { panels().contains { $0[kCGWindowName as String] as? String == "Skippy · " + name } }
}
key(kVK_Escape)
check("Escape dismisses the final tool") { panels().isEmpty }

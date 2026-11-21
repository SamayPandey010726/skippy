import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
  let shortcut: GlobalShortcut
  var title = "Global Skippy shortcut"
  let onRecord: (GlobalShortcut) -> Bool

  func makeNSView(context: Context) -> ShortcutRecorderButton {
    let button = ShortcutRecorderButton(shortcut: shortcut, onRecord: onRecord)
    button.setAccessibilityLabel(title)
    return button
  }

  func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
    button.shortcut = shortcut
    if !button.isRecording { button.show(shortcut.displayName) }
  }
}

struct CourierShortcutRecorder: NSViewRepresentable {
  let command: CourierCommand
  let binding: CourierKeyBinding
  let onRecord: (CourierCommand, CourierKeyBinding) -> Bool
  func makeNSView(context: Context) -> CourierShortcutRecorderButton {
    CourierShortcutRecorderButton(command: command, binding: binding, onRecord: onRecord)
  }
  func updateNSView(_ button: CourierShortcutRecorderButton, context: Context) {
    button.binding = binding
    if !button.isRecording { button.show(binding.displayName) }
  }
}

final class CourierShortcutRecorderButton: NSButton {
  let command: CourierCommand
  var binding: CourierKeyBinding
  let onRecord: (CourierCommand, CourierKeyBinding) -> Bool
  private(set) var isRecording = false
  init(command: CourierCommand, binding: CourierKeyBinding,
       onRecord: @escaping (CourierCommand, CourierKeyBinding) -> Bool) {
    self.command = command; self.binding = binding; self.onRecord = onRecord
    super.init(frame: .zero)
    isBordered = false; wantsLayer = true; layer?.cornerRadius = 8; layer?.borderWidth = 1
    target = self; action = #selector(beginRecording); show(binding.displayName); updateAppearance()
    toolTip = "Click, then press a key combination"
    setAccessibilityLabel("\(command.title) shortcut")
  }
  required init?(coder: NSCoder) { nil }
  override var acceptsFirstResponder: Bool { true }
  @objc private func beginRecording() { isRecording = true; show("Press keys…"); window?.makeFirstResponder(self) }
  override func keyDown(with event: NSEvent) {
    guard isRecording else { super.keyDown(with: event); return }
    if event.keyCode == 53 { isRecording = false; show(binding.displayName); return }
    let candidate = CourierKeyBinding(event: event)
    guard onRecord(command, candidate) else { NSSound.beep(); show("Already used"); return }
    binding = candidate; isRecording = false; show(candidate.displayName)
  }
  override func resignFirstResponder() -> Bool { isRecording = false; show(binding.displayName); return super.resignFirstResponder() }
  func show(_ value: String) {
    attributedTitle = NSAttributedString(string: value, attributes: [
      .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor])
  }
  private func updateAppearance() {
    layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
    layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
  }
}

final class ShortcutRecorderButton: NSButton {
  var shortcut: GlobalShortcut
  let onRecord: (GlobalShortcut) -> Bool
  private(set) var isRecording = false

  init(shortcut: GlobalShortcut, onRecord: @escaping (GlobalShortcut) -> Bool) {
    self.shortcut = shortcut
    self.onRecord = onRecord
    super.init(frame: .zero)
    show(shortcut.displayName)
    target = self
    action = #selector(beginRecording)
    isBordered = false
    setButtonType(.momentaryPushIn)
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.borderWidth = 1
    updateAppearance()
    toolTip = "Click, then press your preferred shortcut"
    setAccessibilityLabel("Global Skippy shortcut")
    setAccessibilityHelp("Click, then press a letter or number with at least two modifier keys")
  }

  required init?(coder: NSCoder) { nil }
  override var acceptsFirstResponder: Bool { true }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateAppearance()
    show(isRecording ? "Press shortcut…" : shortcut.displayName)
  }

  @objc private func beginRecording() {
    isRecording = true
    show("Press shortcut…")
    window?.makeFirstResponder(self)
  }

  override func keyDown(with event: NSEvent) {
    guard isRecording else { super.keyDown(with: event); return }
    if event.keyCode == 53 {
      finishRecording()
      return
    }
    guard let candidate = GlobalShortcut(event: event) else {
      NSSound.beep(); show("Try 2+ modifiers"); return
    }
    guard onRecord(candidate) else {
      NSSound.beep(); show("Already used"); return
    }
    shortcut = candidate
    finishRecording()
  }

  override func resignFirstResponder() -> Bool {
    finishRecording()
    return super.resignFirstResponder()
  }

  private func finishRecording() {
    isRecording = false
    show(shortcut.displayName)
  }

  func show(_ value: String) {
    attributedTitle = NSAttributedString(
      string: value,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
        .foregroundColor: NSColor.labelColor,
      ])
  }

  private func updateAppearance() {
    layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
    layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
  }
}

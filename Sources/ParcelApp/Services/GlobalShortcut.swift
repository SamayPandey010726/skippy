import AppKit
import Carbon

struct GlobalShortcut: Equatable, Sendable {
  static let defaultShortcut = GlobalShortcut(
    keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | optionKey | cmdKey), keyLabel: "P")

  let keyCode: UInt32
  let modifiers: UInt32
  let keyLabel: String

  var displayName: String {
    var value = ""
    if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
    return value + keyLabel.uppercased()
  }

  var spokenName: String {
    var parts: [String] = []
    if modifiers & UInt32(controlKey) != 0 { parts.append("Control") }
    if modifiers & UInt32(optionKey) != 0 { parts.append("Option") }
    if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
    if modifiers & UInt32(cmdKey) != 0 { parts.append("Command") }
    parts.append(keyLabel.uppercased())
    return parts.joined(separator: " + ")
  }

  var isValid: Bool {
    let known = [UInt32(controlKey), UInt32(optionKey), UInt32(shiftKey), UInt32(cmdKey)]
    let modifierCount = known.filter { modifiers & $0 != 0 }.count
    let hasPrimaryModifier = modifiers & UInt32(controlKey | optionKey | cmdKey) != 0
    return modifierCount >= 2 && hasPrimaryModifier && !keyLabel.trimmingCharacters(in: .whitespaces).isEmpty
  }

  init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.keyLabel = keyLabel
  }

  init?(event: NSEvent) {
    let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
    var carbonModifiers: UInt32 = 0
    if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
    if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
    if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
    if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
    let label = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.init(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers, keyLabel: label)
    guard isValid else { return nil }
  }

  static func load(defaults: UserDefaults = .standard) -> GlobalShortcut {
    guard defaults.object(forKey: Keys.code) != nil,
      defaults.object(forKey: Keys.modifiers) != nil,
      let label = defaults.string(forKey: Keys.label)
    else { return .defaultShortcut }
    let shortcut = GlobalShortcut(
      keyCode: UInt32(defaults.integer(forKey: Keys.code)),
      modifiers: UInt32(defaults.integer(forKey: Keys.modifiers)), keyLabel: label)
    return shortcut.isValid ? shortcut : .defaultShortcut
  }

  func save(defaults: UserDefaults = .standard) {
    defaults.set(Int(keyCode), forKey: Keys.code)
    defaults.set(Int(modifiers), forKey: Keys.modifiers)
    defaults.set(keyLabel, forKey: Keys.label)
  }

  private enum Keys {
    static let code = "parcel.globalShortcut.keyCode"
    static let modifiers = "parcel.globalShortcut.modifiers"
    static let label = "parcel.globalShortcut.keyLabel"
  }
}

@MainActor final class GlobalShortcutManager: ObservableObject {
  static let shared = GlobalShortcutManager()

  @Published private(set) var shortcut: GlobalShortcut
  @Published private(set) var message = "Works from any app."

  private let defaults: UserDefaults
  private var hotKey: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  private var action: (() -> Void)?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    shortcut = GlobalShortcut.load(defaults: defaults)
  }

  func install(action: @escaping () -> Void) {
    self.action = action
    if eventHandler == nil {
      var specification = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
      InstallEventHandler(
        GetApplicationEventTarget(),
        { _, _, pointer in
          guard let pointer else { return OSStatus(eventNotHandledErr) }
          let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(pointer).takeUnretainedValue()
          Task { @MainActor in manager.action?() }
          return noErr
        }, 1, &specification, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }
    let result = register(shortcut)
    if result != noErr {
      message = result == eventHotKeyExistsErr
        ? "The saved shortcut is already used. Choose another combination."
        : "The saved shortcut could not be registered. Choose another combination."
    }
  }

  @discardableResult func update(_ candidate: GlobalShortcut) -> Bool {
    guard candidate.isValid else {
      message = "Use a letter or number with at least two modifier keys."
      return false
    }
    let previous = shortcut
    unregister()
    let result = register(candidate)
    guard result == noErr else {
      _ = register(previous)
      message = result == eventHotKeyExistsErr
        ? "That shortcut is already used. Try another combination."
        : "That shortcut could not be registered. Try another combination."
      return false
    }
    shortcut = candidate
    candidate.save(defaults: defaults)
    message = "Saved — \(candidate.spokenName) now opens Parcels."
    return true
  }

  func reset() { _ = update(.defaultShortcut) }

  @discardableResult private func register(_ value: GlobalShortcut) -> OSStatus {
    let identifier = EventHotKeyID(signature: 0x5052_434C, id: 1)
    let result = RegisterEventHotKey(
      value.keyCode, value.modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey)
    if result == noErr { message = "Works from any app." }
    return result
  }

  private func unregister() {
    guard let hotKey else { return }
    UnregisterEventHotKey(hotKey)
    self.hotKey = nil
  }
}

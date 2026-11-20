import AppKit
import Carbon

enum CourierCommand: String, CaseIterable, Identifiable {
  case chooseArrow, nextFile, previousFile, search, filters, pack, copy, paste, clipboard, tools, processMedia, ocr, settings, open, close
  case cycleTheme, cycleEmblem, browsePins
  var id: String { rawValue }
  var title: String {
    switch self {
    case .browsePins: return "Browse pinned arrows"
    case .cycleTheme: return "Switch light / dark"
    case .cycleEmblem: return "Change launcher icon"
    case .chooseArrow: return "Find an arrow"
    case .nextFile: return "Next widget page"
    case .previousFile: return "Previous widget page"
    case .search: return "Search"
    case .filters: return "Filters"
    case .pack: return "Pack parcel"
    case .copy: return "Copy file / parcel"
    case .paste: return "Paste into parcel"
    case .clipboard: return "Clipboard history"
    case .tools: return "Widget dashboard"
    case .processMedia: return "Process image or video"
    case .ocr: return "Copy image text (OCR)"
    case .settings: return "Open settings"
    case .open: return "Open focused file"
    case .close: return "Close Skippy"
    }
  }
  var defaultBinding: CourierKeyBinding {
    switch self {
    case .browsePins: return .init(keyCode: UInt16(kVK_ANSI_B), modifiers: NSEvent.ModifierFlags([.option, .shift]).rawValue, keyLabel: "B")
    case .cycleTheme: return .init(keyCode: UInt16(kVK_ANSI_T), modifiers: NSEvent.ModifierFlags([.option, .shift]).rawValue, keyLabel: "T")
    case .cycleEmblem: return .init(keyCode: UInt16(kVK_ANSI_I), modifiers: NSEvent.ModifierFlags([.option, .shift]).rawValue, keyLabel: "I")
    case .chooseArrow: return .init(keyCode: UInt16(kVK_ANSI_K), modifiers: NSEvent.ModifierFlags.command.rawValue, keyLabel: "K")
    case .nextFile: return .init(keyCode: UInt16(kVK_Tab), modifiers: 0, keyLabel: "Tab")
    case .previousFile: return .init(keyCode: UInt16(kVK_Tab), modifiers: NSEvent.ModifierFlags.shift.rawValue, keyLabel: "Tab")
    case .search: return .init(keyCode: UInt16(kVK_ANSI_Slash), modifiers: 0, keyLabel: "/")
    case .filters: return .init(keyCode: UInt16(kVK_ANSI_Slash), modifiers: NSEvent.ModifierFlags.shift.rawValue, keyLabel: "/")
    case .pack: return .init(keyCode: UInt16(kVK_ANSI_P), modifiers: NSEvent.ModifierFlags.command.rawValue, keyLabel: "P")
    case .copy: return .init(keyCode: UInt16(kVK_ANSI_C), modifiers: NSEvent.ModifierFlags.command.rawValue, keyLabel: "C")
    case .paste: return .init(keyCode: UInt16(kVK_ANSI_V), modifiers: NSEvent.ModifierFlags.command.rawValue, keyLabel: "V")
    case .clipboard: return .init(keyCode: UInt16(kVK_ANSI_C), modifiers: NSEvent.ModifierFlags.option.rawValue, keyLabel: "C")
    case .tools: return .init(keyCode: UInt16(kVK_ANSI_T), modifiers: NSEvent.ModifierFlags.option.rawValue, keyLabel: "T")
    case .processMedia: return .init(keyCode: UInt16(kVK_ANSI_P), modifiers: NSEvent.ModifierFlags.option.rawValue, keyLabel: "P")
    case .ocr: return .init(keyCode: UInt16(kVK_ANSI_O), modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue, keyLabel: "O")
    case .settings: return .init(keyCode: UInt16(kVK_ANSI_S), modifiers: NSEvent.ModifierFlags.command.rawValue, keyLabel: "S")
    case .open: return .init(keyCode: UInt16(kVK_Return), modifiers: 0, keyLabel: "Return")
    case .close: return .init(keyCode: UInt16(kVK_Escape), modifiers: 0, keyLabel: "Esc")
    }
  }
}

struct CourierKeyBinding: Codable, Equatable {
  let keyCode: UInt16
  let modifiers: UInt
  let keyLabel: String
  init(keyCode: UInt16, modifiers: UInt, keyLabel: String) {
    self.keyCode = keyCode; self.modifiers = modifiers; self.keyLabel = keyLabel
  }
  init(event: NSEvent) {
    let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
    let special: [UInt16: String] = [UInt16(kVK_Tab): "Tab", UInt16(kVK_Return): "Return",
      UInt16(kVK_Escape): "Esc", UInt16(kVK_Space): "Space", UInt16(kVK_Delete): "Delete"]
    self.init(keyCode: event.keyCode, modifiers: flags.rawValue,
      keyLabel: special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key")
  }
  var displayName: String {
    var value = ""
    let flags = NSEvent.ModifierFlags(rawValue: modifiers)
    if flags.contains(.control) { value += "⌃" }
    if flags.contains(.option) { value += "⌥" }
    if flags.contains(.shift) { value += "⇧" }
    if flags.contains(.command) { value += "⌘" }
    switch keyLabel {
    case "Tab": return value + "⇥"
    case "Return": return value + "↩"
    default: return value + keyLabel
    }
  }
  func matches(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
    return event.keyCode == keyCode && flags.rawValue == modifiers
  }
}

@MainActor final class CourierShortcutStore: ObservableObject {
  static let shared = CourierShortcutStore()
  @Published private(set) var bindings: [CourierCommand: CourierKeyBinding] = [:]
  private let defaults: UserDefaults
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    for command in CourierCommand.allCases {
      if let data = defaults.data(forKey: key(command)), let saved = try? JSONDecoder().decode(CourierKeyBinding.self, from: data) {
        bindings[command] = saved
      } else { bindings[command] = command.defaultBinding }
    }
  }
  func binding(for command: CourierCommand) -> CourierKeyBinding { bindings[command] ?? command.defaultBinding }
  func command(for event: NSEvent) -> CourierCommand? {
    CourierCommand.allCases.first { binding(for: $0).matches(event) }
  }
  @discardableResult func update(_ command: CourierCommand, binding: CourierKeyBinding) -> Bool {
    guard !bindings.contains(where: { $0.key != command && $0.value.keyCode == binding.keyCode && $0.value.modifiers == binding.modifiers }) else { return false }
    bindings[command] = binding
    if let data = try? JSONEncoder().encode(binding) { defaults.set(data, forKey: key(command)) }
    return true
  }
  func reset(_ command: CourierCommand) { _ = update(command, binding: command.defaultBinding) }
  func resetAll() {
    for command in CourierCommand.allCases { defaults.removeObject(forKey: key(command)) }
    bindings = Dictionary(uniqueKeysWithValues: CourierCommand.allCases.map { ($0, $0.defaultBinding) })
  }
  private func key(_ command: CourierCommand) -> String { "parcel.courierShortcut." + command.rawValue }
}

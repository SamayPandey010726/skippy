import AppKit
import Carbon

struct GlobalShortcut: Codable, Equatable, Sendable {
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

enum WorkspaceShortcut: Hashable, Identifiable {
  case launcher
  case arrow(NotchModule)

  static var all: [Self] { [.launcher] + NotchModule.allCases.filter { $0 != .dashboard }.map(Self.arrow) }
  var id: String {
    switch self {
    case .launcher: "launcher"
    case .arrow(let module): "arrow." + module.rawValue
    }
  }
  var title: String {
    switch self {
    case .launcher: "Open Skippy"
    case .arrow(let module): module.title
    }
  }
  var eventID: UInt32 {
    guard let index = Self.all.firstIndex(of: self) else { return 0 }
    return 2 + UInt32(index)
  }
  var defaultValue: GlobalShortcut {
    switch self {
    case .launcher:
      return .init(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "S")
    case .arrow(let module):
      let keys: [NotchModule: (Int, String)] = [
        .parcel: (kVK_ANSI_F, "F"), .clipboard: (kVK_ANSI_C, "C"),
        .extract: (kVK_ANSI_E, "E"), .color: (kVK_ANSI_I, "I"),
        .timer: (kVK_ANSI_T, "T"), .notes: (kVK_ANSI_N, "N"),
        .qr: (kVK_ANSI_Q, "Q"), .search: (kVK_ANSI_S, "S"),
        .launcher: (kVK_ANSI_A, "A"), .music: (kVK_ANSI_M, "M"),
        .downloads: (kVK_ANSI_D, "D"), .awake: (kVK_ANSI_W, "W"),
        .recent: (kVK_ANSI_R, "R"), .system: (kVK_ANSI_Y, "Y"),
        .calendar: (kVK_ANSI_L, "L"), .calculator: (kVK_ANSI_K, "K"),
        .screenshot: (kVK_ANSI_4, "4"), .draw: (kVK_ANSI_B, "B"),
        .convert: (kVK_ANSI_V, "V"), .compress: (kVK_ANSI_Z, "Z"), .extractArchive: (kVK_ANSI_X, "X"),
      ]
      let (code, label) = keys[module] ?? (kVK_ANSI_0, "0")
      return .init(keyCode: UInt32(code), modifiers: UInt32(controlKey | optionKey | cmdKey), keyLabel: label)
    }
  }
}

@MainActor final class GlobalShortcutManager: ObservableObject {
  static let shared = GlobalShortcutManager()
  @Published private(set) var shortcut: GlobalShortcut
  @Published private(set) var message = "Works from any app."
  @Published private(set) var workspace: [WorkspaceShortcut: GlobalShortcut] = [:]
  @Published private(set) var unavailable: Set<WorkspaceShortcut> = []

  nonisolated private static let signature: OSType = 0x5052_434C
  private let defaults: UserDefaults
  private var hotKeys: [UInt32: EventHotKeyRef] = [:]
  private var eventHandler: EventHandlerRef?
  private var action: (() -> Void)?
  private var workspaceAction: ((WorkspaceShortcut) -> Void)?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    shortcut = GlobalShortcut.load(defaults: defaults)
    for target in WorkspaceShortcut.all {
      let saved = defaults.data(forKey: "skippy.shortcut." + target.id)
        .flatMap { try? JSONDecoder().decode(GlobalShortcut.self, from: $0) }
      workspace[target] = saved.flatMap { $0.isValid ? $0 : nil } ?? target.defaultValue
    }
  }

  func install(action: @escaping () -> Void) {
    self.action = action
    if eventHandler == nil {
      var specification = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
      InstallEventHandler(
        GetApplicationEventTarget(),
        { _, event, pointer in
          guard let pointer, let event else { return OSStatus(eventNotHandledErr) }
          var identifier = EventHotKeyID()
          let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID), nil, numericCast(MemoryLayout<EventHotKeyID>.size), nil, &identifier)
          if result != noErr || identifier.signature != GlobalShortcutManager.signature {
            return OSStatus(eventNotHandledErr)
          }
          let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(pointer).takeUnretainedValue()
          let id = identifier.id
          Task { @MainActor in manager.perform(id) }
          return noErr
        }, 1, &specification, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }
    unregister(1)
    message = register(shortcut, id: 1) == noErr ? "Works from any app." : "The saved shortcut is unavailable."
  }

  func installWorkspace(action: @escaping (WorkspaceShortcut) -> Void) {
    workspaceAction = action
    for target in WorkspaceShortcut.all {
      unregister(target.eventID)
      updateAvailability(target, result: register(binding(for: target), id: target.eventID))
    }
  }

  func binding(for target: WorkspaceShortcut) -> GlobalShortcut { workspace[target] ?? target.defaultValue }

  @discardableResult func update(_ candidate: GlobalShortcut) -> Bool {
    guard candidate.isValid, !workspace.values.contains(where: { sameKeys($0, candidate) }),
      swap(candidate, previous: shortcut, id: 1) else {
      message = "That shortcut is unavailable. Try another combination."
      return false
    }
    shortcut = candidate
    candidate.save(defaults: defaults)
    message = "Saved. \(candidate.spokenName) opens File Shelf with your selection."
    return true
  }

  @discardableResult func update(_ target: WorkspaceShortcut, _ candidate: GlobalShortcut) -> Bool {
    guard candidate.isValid, !sameKeys(candidate, shortcut),
      !workspace.contains(where: { $0.key != target && sameKeys($0.value, candidate) }),
      swap(candidate, previous: binding(for: target), id: target.eventID) else {
      if hotKeys[target.eventID] == nil { unavailable.insert(target) }
      return false
    }
    unavailable.remove(target)
    workspace[target] = candidate
    if let data = try? JSONEncoder().encode(candidate) { defaults.set(data, forKey: "skippy.shortcut." + target.id) }
    return true
  }

  func reset() { _ = update(.defaultShortcut) }

  private func perform(_ id: UInt32) {
    // Registered combinations must reach the Settings recorder when it is editing a binding.
    if let recorder = NSApp.keyWindow?.firstResponder as? ShortcutRecorderButton, recorder.isRecording { return }
    if id == 1 { action?() }
    else if let target = WorkspaceShortcut.all.first(where: { $0.eventID == id }) { workspaceAction?(target) }
  }

  private func updateAvailability(_ target: WorkspaceShortcut, result: OSStatus) {
    if result == noErr { unavailable.remove(target) } else { unavailable.insert(target) }
  }

  private func sameKeys(_ lhs: GlobalShortcut, _ rhs: GlobalShortcut) -> Bool {
    lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
  }

  private func swap(_ value: GlobalShortcut, previous: GlobalShortcut, id: UInt32) -> Bool {
    if value.keyCode == previous.keyCode, value.modifiers == previous.modifiers, hotKeys[id] != nil { return true }
    let hadPrevious = hotKeys[id] != nil
    unregister(id)
    if register(value, id: id) == noErr { return true }
    if hadPrevious { _ = register(previous, id: id) }
    return false
  }

  private func register(_ value: GlobalShortcut, id: UInt32) -> OSStatus {
    let identifier = EventHotKeyID(signature: Self.signature, id: id)
    var reference: EventHotKeyRef?
    let result = RegisterEventHotKey(
      value.keyCode, value.modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
    if let reference, result == noErr { hotKeys[id] = reference }
    return result
  }

  private func unregister(_ id: UInt32) {
    guard let reference = hotKeys.removeValue(forKey: id) else { return }
    UnregisterEventHotKey(reference)
  }
}

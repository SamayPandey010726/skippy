import AppKit
import Combine

enum QuickPinPosition: Int, CaseIterable, Codable, Identifiable {
  case upperLeft, top, upperRight, right, lowerRight, bottom, lowerLeft, left
  var id: Self { self }
  var title: String {
    switch self {
    case .upperLeft: "Top left"
    case .top: "Top"
    case .upperRight: "Top right"
    case .right: "Right"
    case .lowerRight: "Bottom right"
    case .bottom: "Bottom"
    case .lowerLeft: "Bottom left"
    case .left: "Left"
    }
  }
  var offset: CGPoint {
    let angle = 3 * CGFloat.pi / 4 - CGFloat(rawValue) * .pi / 4
    return CGPoint(x: 87 * cos(angle), y: 87 * sin(angle))
  }
}

struct QuickPin: Codable, Identifiable, Equatable {
  var id: String
  var position: QuickPinPosition
  var alwaysVisible: Bool?
  var module: NotchModule? { NotchModule(rawValue: id) }
}

@MainActor final class QuickPinStore: ObservableObject {
  static let shared = QuickPinStore()
  @Published private(set) var pins: [QuickPin] = [] {
    didSet { if let data = try? JSONEncoder().encode(pins) { defaults.set(data, forKey: "skippy.quickPins") } }
  }
  @Published var alwaysVisible: Bool {
    didSet { defaults.set(alwaysVisible, forKey: "skippy.alwaysShowPins") }
  }
  private let defaults: UserDefaults
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    alwaysVisible = defaults.bool(forKey: "skippy.alwaysShowPins")
    pins = defaults.data(forKey: "skippy.quickPins").flatMap { try? JSONDecoder().decode([QuickPin].self, from: $0) } ?? []
  }
  func contains(_ id: String) -> Bool { pins.contains { $0.id == id } }
  func isAlwaysVisible(_ pin: QuickPin) -> Bool { pin.alwaysVisible ?? alwaysVisible }
  func toggle(_ id: String) {
    if let index = pins.firstIndex(where: { $0.id == id }) { pins.remove(at: index); return }
    let occupied = Set(pins.prefix(3).map(\.position))
    let position = [QuickPinPosition.upperRight, .upperLeft, .bottom].first { !occupied.contains($0) } ?? .right
    pins.append(.init(id: id, position: position))
  }
  func position(_ id: String, at slot: QuickPinPosition) {
    guard let source = pins.firstIndex(where: { $0.id == id }) else { return }
    var revised = pins
    if let occupied = revised.prefix(3).firstIndex(where: { $0.position == slot }), occupied != source {
      revised[occupied].position = revised[source].position
    }
    revised[source].position = slot
    pins = revised
  }
  func setVisibility(_ id: String, always: Bool?) {
    guard let index = pins.firstIndex(where: { $0.id == id }) else { return }
    pins[index].alwaysVisible = always
  }
  func move(_ id: String, by amount: Int) {
    guard let index = pins.firstIndex(where: { $0.id == id }), pins.indices.contains(index + amount) else { return }
    pins.swapAt(index, index + amount)
  }
}

final class QuickPinButton: NSButton {
  var hover: ((Bool) -> Void)?
  var open: (() -> Void)?
  var movePin: ((CGPoint) -> Void)?
  private var tracking: NSTrackingArea?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
    addTrackingArea(area)
    tracking = area
  }
  override func mouseEntered(with event: NSEvent) { hover?(true) }
  override func mouseExited(with event: NSEvent) { hover?(false) }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {
    guard let window, let movePin else { super.mouseDown(with: event); return }
    let first = NSEvent.mouseLocation
    let origin = window.frame.origin
    var moved = false
    while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
      let pointer = NSEvent.mouseLocation
      let dx = pointer.x - first.x, dy = pointer.y - first.y
      if next.type == .leftMouseUp {
        if moved { movePin(CGPoint(x: window.frame.midX, y: window.frame.midY)) }
        else if window.frame.contains(pointer) { open?() }
        return
      }
      if moved || hypot(dx, dy) > 4 {
        moved = true
        window.setFrameOrigin(CGPoint(x: origin.x + dx, y: origin.y + dy))
      }
    }
  }
  @objc func activatePin() { open?() }
}

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum ShelfRanking {
  public static func primary(_ boxes: [ParcelBox]) -> ParcelBox? {
    destinations(boxes, limit: 1).first
  }
  public static func sideRecent(_ boxes: [ParcelBox]) -> [ParcelBox] {
    let primaryID = primary(boxes)?.id
    return destinations(boxes.filter { $0.id != primaryID }, limit: 1)
  }
  public static func normalizePins(_ boxes: [ParcelBox]) -> [ParcelBox] {
    let keeper = destinations(boxes).first(where: \.isShelfPinned)?.id
    return boxes.map { box in
      var result = box
      if box.isShelfPinned { result.isPinned = box.id == keeper }
      return result
    }
  }
  public static func destinations(_ boxes: [ParcelBox], limit: Int = 4) -> [ParcelBox] {
    Array(boxes.enumerated().sorted { left, right in
      let leftPinned = left.element.isShelfPinned
      let rightPinned = right.element.isShelfPinned
      if leftPinned != rightPinned { return leftPinned }
      if left.element.updatedAt != right.element.updatedAt {
        return left.element.updatedAt > right.element.updatedAt
      }
      return left.offset < right.offset
    }.prefix(max(0, limit)).map(\.element))
  }
}

public enum CourierLayout {
  public static let defaultIconSize: CGFloat = 88
  public static let controlSize: CGFloat = 32
  public static let compactSize = courierSize(iconSize: defaultIconSize)
  public static func boundedIconSize(_ value: CGFloat) -> CGFloat {
    value.isFinite ? min(128, max(64, value)) : defaultIconSize
  }
  public static func boundedControlScale(_ value: CGFloat) -> CGFloat {
    value.isFinite ? min(1.75, max(0.75, value)) : 1
  }
  public static func boundedInterfaceScale(_ value: CGFloat) -> CGFloat {
    value.isFinite ? min(1.5, max(0.75, value)) : 1
  }
  public static func buttonSize(iconSize: CGFloat, scale: CGFloat) -> CGFloat {
    max(controlSize, min(80, controlSize * boundedIconSize(iconSize) / defaultIconSize * boundedControlScale(scale)))
  }
  public static func courierSize(iconSize: CGFloat, closeScale: CGFloat = 1, expandScale: CGFloat = 1) -> CGSize {
    let icon = boundedIconSize(iconSize)
    let close = buttonSize(iconSize: icon, scale: closeScale)
    let expand = buttonSize(iconSize: icon, scale: expandScale)
    return CGSize(width: max(icon + 16, close + expand + 24), height: icon + max(close, expand) + 8)
  }
  public static let chooserSize = CGSize(width: 320, height: 216)
  public static let expandedSize = CGSize(width: 320, height: 442)

  public static func contentsSize(itemCount: Int, packed: Bool, showStatus: Bool) -> CGSize {
    CGSize(width: expandedSize.width,
           height: 276 + CGFloat(max(1, min(3, itemCount))) * 36 + (packed ? 32 : 0) + (showStatus ? 26 : 0))
  }

  public static func frame(topRight: CGPoint, screen: CGRect, expanded: Bool,
                           showingContents: Bool = true, requestedSize: CGSize? = nil) -> CGRect {
    let width = min(expandedSize.width, max(1, screen.width - 24))
    let height = min(expandedSize.height, max(1, screen.height - 24))
    let right = min(max(topRight.x, screen.minX + width + 12), screen.maxX - 12)
    let top = min(max(topRight.y, screen.minY + height + 12), screen.maxY - 12)
    let desired = requestedSize ?? (showingContents ? expandedSize : chooserSize)
    let size = expanded ? CGSize(width: min(width, desired.width), height: min(desired.height, height))
      : CGSize(width: min(compactSize.width, width), height: min(compactSize.height, height))
    return CGRect(x: right - size.width, y: top - size.height, width: size.width, height: size.height)
  }
}

public enum CourierSide: String, Codable, CaseIterable, Sendable {
  case left, right, top, bottom
  public var isVertical: Bool { self == .top || self == .bottom }
}
public enum CourierViewStyle: String, Codable, CaseIterable, Sendable {
  case grid, dial, list
}

public struct CourierPlacement: Equatable, Sendable {
  public var frame: CGRect
  public var courier: CGRect
  public var pane: CGRect?
  public var side: CourierSide
  public init(frame: CGRect, courier: CGRect, pane: CGRect?, side: CourierSide) {
    self.frame = frame; self.courier = courier; self.pane = pane; self.side = side
  }
}

public enum CourierSideLayout {
  public static let choices = CGSize(width: 112, height: 48)
  public static let folder = CGSize(width: 320, height: 390)
  public static let fan = CGSize(width: 360, height: 700)
  public static func fanSize(itemCount: Int) -> CGSize {
    CGSize(width: fan.width, height: itemCount <= 0 ? 340 : (itemCount == 1 ? 400 : (itemCount == 2 ? 460 : (itemCount == 3 ? 540 : fan.height))))
  }
  public static func newOptionPlacement(courier: CGRect, screen: CGRect, size: CGSize = choices) -> CourierPlacement {
    let available = screen.insetBy(dx: 8, dy: 8)
    var anchor = courier
    anchor.origin.x = min(anchor.minX, available.maxX - anchor.width - size.width - 12)
    anchor.origin.y = max(anchor.minY, available.minY + size.height + 12)
    let pane = CGRect(x: anchor.maxX + 12, y: anchor.minY - size.height - 12, width: size.width, height: size.height)
    let frame = anchor.union(pane)
    return CourierPlacement(frame: frame, courier: anchor.offsetBy(dx: -frame.minX, dy: -frame.minY),
      pane: pane.offsetBy(dx: -frame.minX, dy: -frame.minY), side: .bottom)
  }
  public static func dialPlacement(courier: CGRect, iconCenter: CGPoint, screen: CGRect, side: CourierSide,
    radius: CGFloat = 140, scale: CGFloat = 1, count: Int = 5, headerHeight: CGFloat = 116) -> CourierPlacement {
    let available = screen.insetBy(dx: 8, dy: 8)
    var bounds = courier
    for slot in CourierFanLayout.slots(index: 0, count: count).filter({ abs($0.offset) <= 2 }) {
      var point = CourierFanLayout.anchoredCenter(offset: slot.offset, origin: iconCenter, side: side, radius: radius, count: count)
      point.y = iconCenter.y - (point.y - iconCenter.y)
      bounds = bounds.union(CGRect(x: point.x - 50 * scale, y: point.y - 60 * scale, width: 100 * scale, height: 120 * scale))
    }
    if count == 0 { bounds = CGRect(x: bounds.minX, y: bounds.minY - 50 * scale, width: bounds.width, height: bounds.height + 50 * scale) }
    bounds = bounds.union(CGRect(x: bounds.midX - 170 * scale, y: bounds.maxY + 8 * scale,
      width: 340 * scale, height: headerHeight * scale))
    let size = CGSize(width: min(bounds.width, available.width), height: min(bounds.height, available.height))
    let origin = CGPoint(x: min(max(bounds.minX, available.minX), available.maxX - size.width),
      y: min(max(bounds.minY, available.minY), available.maxY - size.height))
    let shift = CGPoint(x: origin.x - bounds.minX, y: origin.y - bounds.minY)
    let frame = CGRect(origin: origin, size: size)
    return CourierPlacement(frame: frame, courier: courier.offsetBy(dx: shift.x - frame.minX, dy: shift.y - frame.minY),
      pane: CGRect(origin: .zero, size: size), side: side)
  }
  public static func placement(courier: CGRect, screen: CGRect, pane: CGSize?, side: CourierSide) -> CourierPlacement {
    guard let pane else {
      return CourierPlacement(frame: courier, courier: CGRect(origin: .zero, size: courier.size), pane: nil, side: side)
    }
    let available = screen.insetBy(dx: 8, dy: 8)
    let size = CGSize(width: min(pane.width, max(1, available.width - (side.isVertical ? 0 : courier.width + 12))),
      height: min(pane.height, max(1, available.height - (side.isVertical ? courier.height + 12 : 0))))
    var anchor = courier
    switch side {
    case .left: anchor.origin.x = max(anchor.minX, available.minX + size.width + 12)
    case .right: anchor.origin.x = min(anchor.minX, available.maxX - size.width - 12 - anchor.width)
    case .top: anchor.origin.y = min(anchor.minY, available.maxY - size.height - 12 - anchor.height)
    case .bottom: anchor.origin.y = max(anchor.minY, available.minY + size.height + 12)
    }
    let horizontal = min(max(anchor.midX - size.width / 2, available.minX), available.maxX - size.width)
    let vertical = min(max(anchor.midY - size.height / 2, available.minY), available.maxY - size.height)
    let origin: CGPoint
    switch side {
    case .left: origin = CGPoint(x: anchor.minX - 12 - size.width, y: vertical)
    case .right: origin = CGPoint(x: anchor.maxX + 12, y: vertical)
    case .top: origin = CGPoint(x: horizontal, y: anchor.maxY + 12)
    case .bottom: origin = CGPoint(x: horizontal, y: anchor.minY - 12 - size.height)
    }
    let paneRect = CGRect(origin: origin, size: size)
    let frame = anchor.union(paneRect)
    return CourierPlacement(frame: frame, courier: anchor.offsetBy(dx: -frame.minX, dy: -frame.minY),
      pane: paneRect.offsetBy(dx: -frame.minX, dy: -frame.minY), side: side)
  }
  public static func menuDialPlacement(courier: CGRect, screen: CGRect, count: Int, scale: CGFloat = 1,
    headerHeight: CGFloat = 116) -> CourierPlacement {
    let available = screen.insetBy(dx: 8, dy: 8)
    let width = min(available.width, max(340, CGFloat(min(5, max(1, count))) * 82 + 16) * scale)
    let height = min(available.height, (headerHeight + 104) * scale)
    let pane = CGRect(x: min(max(courier.midX - width / 2, available.minX), available.maxX - width),
      y: available.maxY - height, width: width, height: height)
    let frame = pane.union(courier)
    return CourierPlacement(frame: frame, courier: courier.offsetBy(dx: -frame.minX, dy: -frame.minY),
      pane: pane.offsetBy(dx: -frame.minX, dy: -frame.minY), side: .bottom)
  }
}

public struct CourierPreviewPlacement: Equatable, Sendable {
  public var shelf: CGRect
  public var preview: CGRect
}

public enum CourierPreviewLayout {
  public static func placement(shelf: CGRect, screen: CGRect, desired: CGSize = CGSize(width: 360, height: 320),
    preferRight: Bool = true) -> CourierPreviewPlacement? {
    let available = screen.insetBy(dx: 8, dy: 8)
    let gap: CGFloat = 12
    let minimum = min(192, desired.width)
    let left = max(0, shelf.minX - available.minX - gap)
    let right = max(0, available.maxX - shelf.maxX - gap)
    var adjusted = shelf
    var onRight = preferRight
    var width = desired.width
    if (preferRight ? right : left) >= desired.width { onRight = preferRight }
    else if (preferRight ? left : right) >= desired.width { onRight = !preferRight }
    else if max(left, right) >= minimum {
      onRight = right >= left
      width = min(desired.width, max(left, right))
    } else {
      width = min(desired.width, available.width - shelf.width - gap)
      guard width >= minimum else { return nil }
      adjusted.origin.x = onRight ? available.minX : available.maxX - shelf.width
    }
    let height = min(desired.height, available.height)
    let preview = CGRect(x: onRight ? adjusted.maxX + gap : adjusted.minX - gap - width,
      y: min(max(adjusted.midY - height / 2, available.minY), available.maxY - height), width: width, height: height)
    return CourierPreviewPlacement(shelf: adjusted, preview: preview)
  }
}

public enum CourierFanLayout {
  public static func straightCenter(offset: Int, size: CGSize, count: Int) -> CGPoint {
    let visible = min(5, max(1, count))
    let center = Double(-(visible - 1) / 2) + Double(visible - 1) / 2
    let spacing = min(82, size.width / CGFloat(visible))
    return CGPoint(x: size.width / 2 + (CGFloat(offset) - center) * spacing, y: size.height / 2)
  }
  public static func anchoredCenter(offset: Int, origin: CGPoint, side: CourierSide, radius: CGFloat, count: Int = 5) -> CGPoint {
    let visible = min(5, max(1, count))
    let center = Double(-(visible - 1) / 2) + Double(visible - 1) / 2
    let spread: Double = visible < 2 ? 0 : (visible == 2 ? 90 : (visible == 3 ? 150 : 180))
    let angle = (Double(offset) - center) * spread / Double(max(1, visible - 1)) * Double.pi / 180
    switch side {
    case .left: return CGPoint(x: origin.x - radius * cos(angle), y: origin.y + radius * sin(angle))
    case .right: return CGPoint(x: origin.x + radius * cos(angle), y: origin.y + radius * sin(angle))
    case .top: return CGPoint(x: origin.x + radius * sin(angle), y: origin.y - radius * cos(angle))
    case .bottom: return CGPoint(x: origin.x + radius * sin(angle), y: origin.y + radius * cos(angle))
    }
  }
  public struct Slot: Equatable, Identifiable, Sendable {
    public var index: Int
    public var offset: Int
    public var id: Int { index }
    public init(index: Int, offset: Int) { self.index = index; self.offset = offset }
  }
  public static func wrappedIndex(_ index: Int, count: Int) -> Int {
    guard count > 0 else { return 0 }
    let remainder = index % count
    return remainder < 0 ? remainder + count : remainder
  }
  public static func slots(index: Int, count: Int) -> [Slot] {
    guard count > 0 else { return [] }
    let visible = min(7, count)
    let first = -(visible - 1) / 2
    return (first..<(first + visible)).map { Slot(index: wrappedIndex(index + $0, count: count), offset: $0) }
  }
  public static func initialIndex(count: Int) -> Int { min(2, max(0, (count - 1) / 2)) }
  public static func boundedIndex(_ index: Int, count: Int) -> Int { min(max(0, count - 1), max(0, index)) }
  public static func visibleIndices(index: Int, count: Int) -> Range<Int> {
    let center = boundedIndex(index, count: count)
    return max(0, center - 3)..<min(max(0, count), center + 4)
  }
  public static func center(offset: Int, size: CGSize, side: CourierSide, count: Int = 5) -> CGPoint {
    if side.isVertical {
      let point = center(offset: offset, size: CGSize(width: size.height, height: size.width), side: .left, count: count)
      return CGPoint(x: point.y, y: side == .top ? point.x : size.height - point.x)
    }
    if count <= 3 {
      let horizontal: CGFloat = count <= 1 ? 0.5 : (offset == 0 ? 0.38 : 0.73)
      let vertical: CGFloat = count <= 1 || offset == 0 ? 0.5 : (offset < 0 ? 0.18 : 0.82)
      return CGPoint(x: size.width * (side == .left ? horizontal : 1 - horizontal), y: size.height * vertical)
    }
    let angle = Double(offset) * 30 * Double.pi / 180
    let radius = min(224, max(1, (size.height / 2 - 46) / sin(60 * Double.pi / 180)))
    let inset = min(40, size.width * 0.12)
    let left = size.width + inset - radius * cos(angle)
    let horizontal = side == .left ? left : size.width - left
    return CGPoint(x: min(max(min(38, size.width / 2), horizontal), max(size.width / 2, size.width - 38)),
      y: min(max(46, size.height / 2 + radius * sin(angle)), max(46, size.height - 46)))
  }
}

public struct CourierDialScroll {
  private var remainder: CGFloat = 0
  public init() {}
  public mutating func steps(delta: CGFloat) -> Int {
    guard delta.isFinite else { return 0 }
    remainder -= min(108, max(-108, delta))
    let steps = Int(remainder / 36)
    remainder -= CGFloat(steps) * 36
    return steps
  }
}

public struct PointerShakeDetector {
  private var previous: CGPoint?
  private var started: TimeInterval = 0
  private var cooldown: TimeInterval = 0
  private var direction: CGFloat = 0
  private var distance: CGFloat = 0
  private var reversals = 0
  public init() {}
  public mutating func update(point: CGPoint, time: TimeInterval, buttonDown: Bool) -> Bool {
    guard !buttonDown else { previous = point; distance = 0; reversals = 0; direction = 0; started = time; return false }
    guard time >= cooldown else { previous = point; return false }
    guard let last = previous else { previous = point; started = time; return false }
    if time - started > 0.7 { started = time; distance = 0; reversals = 0; direction = 0 }
    let horizontal = point.x - last.x
    let vertical = point.y - last.y
    let delta = abs(horizontal) >= abs(vertical) ? horizontal : vertical
    guard abs(delta) >= 18 else { return false }
    previous = point
    let next: CGFloat = delta > 0 ? 1 : -1
    distance += abs(delta)
    if direction != 0 && next != direction { reversals += 1 }
    direction = next
    if reversals >= 3 && distance >= 220 {
      cooldown = time + 2; distance = 0; reversals = 0; direction = 0; return true
    }
    return false
  }
}

public struct ExternalDragSession {
  public private(set) var isDragging = false
  private var baseline: Int
  private var suppressed = false

  public init(pasteboardGeneration: Int) { baseline = pasteboardGeneration }

  public mutating func suppress() {
    suppressed = true
    isDragging = false
  }

  public mutating func update(buttonDown: Bool, pasteboardGeneration: Int, supported: Bool) {
    if !buttonDown {
      baseline = pasteboardGeneration
      suppressed = false
      isDragging = false
    } else if !suppressed, pasteboardGeneration != baseline, supported {
      isDragging = true
    }
  }
}

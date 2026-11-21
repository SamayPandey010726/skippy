import Foundation

public enum QuiverSurface: String, CaseIterable, Identifiable {
  case menu = "Menu bar", notch = "Notch", floating = "Floating", left = "Left edge"
  case right = "Right edge", top = "Top edge", bottom = "Bottom edge", dock = "Dock"
  public var id: Self { self }

  public static func snapped(at point: CGPoint, screen: CGRect, visible: CGRect) -> Self {
    if (visible.minY - screen.minY > 6 && point.y < visible.minY) ||
       (visible.minX - screen.minX > 6 && point.x < visible.minX) ||
       (screen.maxX - visible.maxX > 6 && point.x > visible.maxX) { return .dock }
    if point.y >= visible.maxY - 12 {
      if abs(point.x - screen.midX) < 75 { return .notch }
      if point.x >= screen.maxX - 100 { return .menu }
      return .top
    }
    if point.x < visible.minX + 16 { return .left }
    if point.x > visible.maxX - 16 { return .right }
    if point.y < visible.minY + 16 { return .bottom }
    return .floating
  }

  public static func companionPanel(at anchor: CGRect, within bounds: CGRect, size: CGSize, preferRight: Bool = true) -> CGRect {
    let w = min(size.width, bounds.width), h = min(size.height, bounds.height)
    let right = anchor.maxX + 13
    let left = anchor.minX - w - 13
    let rightFits = right + w <= bounds.maxX
    let leftFits = left >= bounds.minX
    let x = rightFits && (preferRight || !leftFits) ? right : left
    return CGRect(x: min(max(x, bounds.minX), bounds.maxX - w),
      y: min(max(anchor.midY - h * 0.5, bounds.minY), bounds.maxY - h), width: w, height: h)
  }

  public static func panel(at anchor: CGRect, within bounds: CGRect, size: CGSize, sideRail: Bool = false) -> CGRect {
    let w = min(size.width, bounds.width), h = min(size.height, bounds.height)
    if (sideRail || anchor.height > anchor.width * 2), anchor.width <= 34,
       (anchor.minX <= bounds.minX + 1 || anchor.maxX >= bounds.maxX - 1) {
      let x = anchor.midX < bounds.midX ? anchor.maxX + 3 : anchor.minX - w - 3
      return CGRect(x: min(max(x, bounds.minX), bounds.maxX - w),
                    y: min(max(anchor.midY - h / 2, bounds.minY), bounds.maxY - h), width: w, height: h)
    }
    let below = anchor.minY - h - 3
    let y = below >= bounds.minY ? below : anchor.maxY + 3
    return CGRect(x: min(max(anchor.midX - w / 2, bounds.minX), bounds.maxX - w),
      y: min(max(y, bounds.minY), bounds.maxY - h), width: w, height: h)
  }
}

public struct QuiverGeometry {
  public static let floatingDiameter: CGFloat = 60
  public static let wheelRadius: CGFloat = 59

  public let frame: CGRect
  public let mark: CGRect
  public let buttons: [CGRect]

  public init(surface: QuiverSurface, center: CGPoint, bounds: CGRect, count: Int, progress: CGFloat, height: CGFloat, growsRight: Bool) {
    let cell: CGFloat = 31
    let wheel = surface == .floating
    let vertical = surface == .left || surface == .right
    let radius = Self.wheelRadius
    let markWidth: CGFloat = wheel ? Self.floatingDiameter : cell
    let markHeight: CGFloat = wheel ? Self.floatingDiameter : height
    let width = wheel ? markWidth + 2 * radius * progress : (vertical ? cell : cell * (1 + CGFloat(count) * progress))
    let h = wheel ? markHeight + 2 * radius * progress : (vertical ? height + height * CGFloat(count) * progress : height)
    let up = center.y <= bounds.midY
    let mx = wheel ? (width - markWidth) / 2 : (vertical || growsRight ? 0 : width - cell)
    let my = wheel ? (h - markHeight) / 2 : (vertical && !up ? h - height : 0)
    frame = CGRect(x: min(max(center.x - markWidth / 2 - mx, bounds.minX), bounds.maxX - width),
                   y: min(max(center.y - markHeight / 2 - my, bounds.minY), bounds.maxY - h),
                   width: width.rounded(), height: h.rounded())
    mark = CGRect(x: mx.rounded(), y: my.rounded(), width: markWidth, height: markHeight)
    buttons = (0..<count).map { i in
      let angle = CGFloat.pi / 2 - 2 * .pi * CGFloat(i) / CGFloat(max(1, count))
      let delta = (vertical ? height : cell) * CGFloat(i + 1) * progress
      let dx = wheel ? cos(angle) * radius * progress : (vertical ? 0 : (growsRight ? delta : -delta))
      let dy = wheel ? sin(angle) * radius * progress : (vertical ? (up ? delta : -delta) : 0)
      return CGRect(x: (mx + (markWidth - cell) / 2 + dx).rounded(),
        y: (my + (markHeight - height) / 2 + dy).rounded(), width: cell, height: height)
    }
  }
}

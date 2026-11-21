import Foundation
import XCTest
@testable import ParcelCore

final class QuiverGeometryTests: XCTestCase {
  let screen = CGRect(x: -1512, y: 100, width: 1512, height: 920)
  var visible: CGRect { screen.insetBy(dx: 0, dy: 30) }

  func testWheelKeepsItsMarkStillAndSeparatesAllSevenTargets() {
    let center = CGPoint(x: -622.5, y: 502)
    for count in 1...7 {
      for step in 0...20 {
        let fraction = CGFloat(step) / 20
        let wheel = QuiverGeometry(surface: .floating, center: center, bounds: visible,
                                   count: count, progress: fraction, height: 34, growsRight: true)
        let local = wheel.mark
        XCTAssertEqual(wheel.frame.minX + local.midX, center.x, accuracy: 1)
        XCTAssertEqual(wheel.frame.minY + local.midY, center.y, accuracy: 1)
        XCTAssertTrue(visible.contains(wheel.frame))
        if step == 20 {
          for (i, rect) in wheel.buttons.enumerated() {
            XCTAssertFalse(rect.intersects(local))
            XCTAssertEqual(hypot(rect.midX - local.midX, rect.midY - local.midY), 59, accuracy: 1)
            for other in wheel.buttons.dropFirst(i + 1) {
              XCTAssertFalse(rect.intersects(other), "Adjacent targets must be individually selectable")
            }
          }
        }
      }
    }
  }

  func testSideBarsHaveOneColumnAndOpenTheirToolIntoTheDisplay() {
    for surface in [QuiverSurface.left, .right] {
      for y in [visible.minY + 20, visible.maxY - 20] {
        let x = surface == .left ? visible.minX + 15.5 : visible.maxX - 15.5
        let bar = QuiverGeometry(surface: surface, center: CGPoint(x: x, y: y), bounds: visible,
                                 count: 7, progress: 1, height: 34, growsRight: surface == .left)
        XCTAssertEqual(bar.frame.width, 31)
        XCTAssertEqual(Set(bar.buttons.map(\.midX)).count, 1)
        let pane = QuiverSurface.panel(at: bar.frame, within: visible, size: CGSize(width: 460, height: 340))
        XCTAssertTrue(visible.contains(pane))
        XCTAssertFalse(bar.frame.intersects(pane))
      }
    }
  }

  func testDockSnapDistinguishesReservedDockSpaceFromDesktopEdge() {
    XCTAssertEqual(QuiverSurface.snapped(at: CGPoint(x: -700, y: 110), screen: screen, visible: visible), .dock)
    XCTAssertEqual(QuiverSurface.snapped(at: CGPoint(x: -700, y: 134), screen: screen, visible: visible), .bottom)
  }
  func testCompanionPanelOpensBesideThePinAndFlipsAtTheRightEdge() {
    let screen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
    let size = CGSize(width: 278, height: 143)
    let center = CGRect(x: -600, y: 300, width: 28, height: 28)
    let left = QuiverSurface.companionPanel(at: center, within: screen, size: size)
    XCTAssertEqual(left.minX, center.maxX + 13)
    let outward = QuiverSurface.companionPanel(at: center, within: screen, size: size, preferRight: false)
    XCTAssertEqual(outward.maxX, center.minX - 13)
    let edge = CGRect(x: -38, y: 8, width: 28, height: 28)
    let right = QuiverSurface.companionPanel(at: edge, within: screen, size: size)
    XCTAssertEqual(right.maxX, edge.minX - 13)
    XCTAssertTrue(screen.contains(right))
  }

  func testCompanionChecksScoutAndOtherPinsBeforeFlipping() {
    let bounds = CGRect(x: 0, y: 0, width: 1024, height: 720)
    let scout = CGRect(x: 584, y: 525, width: 60, height: 60)
    let pin = CGRect(x: 656, y: 588, width: 42, height: 42)
    let secondPin = CGRect(x: 656, y: 468, width: 42, height: 42)
    let size = CGSize(width: 409, height: 346)
    let panel = QuiverSurface.companionPanel(at: pin, within: bounds, size: size, avoiding: [scout, secondPin])
    XCTAssertTrue(bounds.contains(panel))
    for rect in [scout, pin, secondPin] {
      XCTAssertFalse(panel.intersects(rect), "An expanded tool card must leave Scout and its pins available")
    }
  }
}

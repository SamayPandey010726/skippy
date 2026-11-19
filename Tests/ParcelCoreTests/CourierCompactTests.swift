import XCTest
@testable import ParcelCore

final class CourierCompactTests: XCTestCase {
  func testSidePreviewNeverOverlapsAcrossEdgesDirectionsScreensAndScales() throws {
    for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1280, y: -200, width: 1280, height: 800)] {
      for scale: CGFloat in [0.75, 1, 1.5] {
        for side in CourierSide.allCases {
          for horizontal: CGFloat in [0.1, 0.5, 0.9] {
            let courier = CGRect(x: screen.minX + screen.width * horizontal, y: screen.midY,
              width: 104 * scale, height: 128 * scale)
            let dial = CourierSideLayout.dialPlacement(courier: courier,
              iconCenter: CGPoint(x: courier.midX, y: courier.midY), screen: screen, side: side,
              radius: 150 * scale, scale: scale)
            let pair = try XCTUnwrap(CourierPreviewLayout.placement(shelf: dial.frame, screen: screen,
              desired: CGSize(width: 360 * scale, height: 320 * scale), preferRight: side != .left))
            XCTAssertFalse(pair.shelf.intersects(pair.preview))
            XCTAssertTrue(screen.contains(pair.shelf))
            XCTAssertTrue(screen.contains(pair.preview))
            XCTAssertEqual(pair.shelf.size, dial.frame.size)
            XCTAssertGreaterThanOrEqual(pair.preview.width, 192)
          }
        }
      }
    }
  }
  func testPreviewPrefersAvailableSideMovesOnlyWhenNecessaryAndDeclinesImpossibleFit() throws {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
    let shelf = CGRect(x: 380, y: 100, width: 240, height: 440)
    for preferRight in [false, true] {
      let pair = try XCTUnwrap(CourierPreviewLayout.placement(shelf: shelf, screen: screen, preferRight: preferRight))
      XCTAssertEqual(pair.shelf, shelf)
      XCTAssertEqual(pair.preview.minX > shelf.maxX, preferRight)
    }
    let centered = CGRect(x: 330, y: 100, width: 340, height: 440)
    let constrained = try XCTUnwrap(CourierPreviewLayout.placement(shelf: centered, screen: screen))
    XCTAssertEqual(constrained.shelf, centered)
    XCTAssertLessThan(constrained.preview.width, 360)
    let crowded = CGRect(x: 150, y: 100, width: 500, height: 400)
    let moved = try XCTUnwrap(CourierPreviewLayout.placement(shelf: crowded,
      screen: CGRect(x: 0, y: 0, width: 800, height: 600)))
    XCTAssertNotEqual(moved.shelf.origin, crowded.origin)
    XCTAssertFalse(moved.shelf.intersects(moved.preview))
    XCTAssertNil(CourierPreviewLayout.placement(shelf: CGRect(x: 0, y: 0, width: 540, height: 400),
      screen: CGRect(x: 0, y: 0, width: 640, height: 480)))
  }
  func testMenuDialIsOneStraightRowBelowMenuAcrossCountsAndScale() throws {
    let screen = CGRect(x: -1440, y: -100, width: 1440, height: 900)
    for scale: CGFloat in [0.75, 1, 1.5] {
      for count in [0, 1, 2, 3, 4, 5, 6, 40] {
        let courier = CGRect(x: -70, y: screen.maxY + 2, width: 30, height: 22)
        let layout = CourierSideLayout.menuDialPlacement(courier: courier, screen: screen, count: count, scale: scale)
        let pane = try XCTUnwrap(layout.pane)
        let globalPane = pane.offsetBy(dx: layout.frame.minX, dy: layout.frame.minY)
        XCTAssertTrue(screen.contains(globalPane))
        XCTAssertLessThan(globalPane.maxY, courier.minY)
        let size = CGSize(width: pane.width / scale - 16, height: 88)
        let visible = CourierFanLayout.slots(index: 0, count: count).filter { abs($0.offset) <= 2 }
        let points = visible.map { CourierFanLayout.straightCenter(offset: $0.offset, size: size, count: count) }
        for point in points {
          XCTAssertEqual(point.y, size.height / 2)
          XCTAssertGreaterThanOrEqual(point.x, 30)
          XCTAssertLessThanOrEqual(point.x, size.width - 30)
        }
        for pair in zip(points, points.dropFirst()) { XCTAssertGreaterThan(pair.1.x - pair.0.x, 60) }
      }
    }
  }
  func testSemiCircleCentersStayAtConstantRadiusFromCourierAndUseChosenHalf() {
    let origin = CGPoint(x: 300, y: 300)
    for side in CourierSide.allCases {
      for offset in -2...2 {
        let point = CourierFanLayout.anchoredCenter(offset: offset, origin: origin, side: side, radius: 140)
        XCTAssertEqual(hypot(point.x - origin.x, point.y - origin.y), 140, accuracy: 0.001)
        switch side {
        case .left: XCTAssertLessThanOrEqual(point.x, origin.x + 0.001)
        case .right: XCTAssertGreaterThanOrEqual(point.x, origin.x - 0.001)
        case .top: XCTAssertLessThanOrEqual(point.y, origin.y + 0.001)
        case .bottom: XCTAssertGreaterThanOrEqual(point.y, origin.y - 0.001)
        }
      }
    }
  }
  func testCompactDialPlacementKeepsCourierAndPaneOnScreenAcrossScaleAndDirections() throws {
    for scale: CGFloat in [0.75, 1, 1.5] {
      for side in CourierSide.allCases {
        for screen in [CGRect(x: 0, y: 0, width: 640, height: 480), CGRect(x: -1440, y: -200, width: 1440, height: 900)] {
          let courier = CGRect(x: screen.maxX - 140 * scale, y: screen.minY + 12, width: 104 * scale, height: 128 * scale)
          let center = CGPoint(x: courier.midX, y: courier.midY)
          let layout = CourierSideLayout.dialPlacement(courier: courier, iconCenter: center, screen: screen,
            side: side, radius: 140 * scale, scale: scale)
          XCTAssertEqual(layout.side, side)
          XCTAssertTrue(screen.contains(layout.frame))
          XCTAssertTrue(try XCTUnwrap(layout.pane).contains(layout.courier))
        }
      }
    }
  }
  func testDeliberateHorizontalAndVerticalShakesRestoreButSlowMovementJitterAndDraggingDoNot() {
    for vertical in [false, true] {
      var detector = PointerShakeDetector()
      var detected = false
      for (index, value) in [0.0, 80, 0, 80, 0].enumerated() {
        detected = detector.update(point: vertical ? CGPoint(x: 0, y: value) : CGPoint(x: value, y: 0),
          time: Double(index) * 0.1, buttonDown: false) || detected
      }
      XCTAssertTrue(detected)
    }
    var detector = PointerShakeDetector()
    for index in 0..<100 {
      XCTAssertFalse(detector.update(point: CGPoint(x: index % 2 == 0 ? 4 : -4, y: 0), time: Double(index) * 0.02, buttonDown: false))
    }
    for index in 0..<20 {
      XCTAssertFalse(detector.update(point: CGPoint(x: Double(index) * 40, y: 0), time: 3 + Double(index) * 0.1, buttonDown: false))
      XCTAssertFalse(detector.update(point: CGPoint(x: index % 2 == 0 ? 80 : 0, y: 0), time: 6 + Double(index) * 0.1, buttonDown: true))
    }
  }
}

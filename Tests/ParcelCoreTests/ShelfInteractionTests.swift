import XCTest
@testable import ParcelCore

final class ShelfInteractionTests: XCTestCase {
  func testCloseAndExpandScaleIndependentlyWithTheMainIconWithoutOverlapping() {
    let small = CourierLayout.buttonSize(iconSize: 64, scale: 0.75)
    let large = CourierLayout.buttonSize(iconSize: 128, scale: 1.75)
    XCTAssertEqual(small, 32)
    XCTAssertGreaterThan(large, CourierLayout.buttonSize(iconSize: 88, scale: 1.75))
    for icon: CGFloat in [64, 88, 128] {
      for close: CGFloat in [0.75, 1, 1.75] {
        for expand: CGFloat in [0.75, 1, 1.75] {
          let size = CourierLayout.courierSize(iconSize: icon, closeScale: close, expandScale: expand)
          let first = CourierLayout.buttonSize(iconSize: icon, scale: close)
          let second = CourierLayout.buttonSize(iconSize: icon, scale: expand)
          XCTAssertGreaterThanOrEqual(size.width, first + second + 24)
          XCTAssertGreaterThanOrEqual(size.height, icon + max(first, second))
        }
      }
    }
    XCTAssertEqual(CourierLayout.boundedControlScale(.nan), 1)
  }

  func testFanIsBoundedMirroredAndOnlyKeepsSevenCardsForHugeParcels() {
    XCTAssertEqual(CourierFanLayout.initialIndex(count: 5), 2)
    XCTAssertEqual(CourierFanLayout.initialIndex(count: 0), 0)
    XCTAssertEqual(CourierFanLayout.visibleIndices(index: 5000, count: 10000).count, 7)
    XCTAssertEqual(CourierFanLayout.boundedIndex(500, count: 2), 1)
    XCTAssertTrue(CourierFanLayout.visibleIndices(index: 0, count: 0).isEmpty)
    for size in [CGSize(width: 344, height: 380), CGSize(width: 220, height: 240)] {
      for offset in -2...2 {
        let left = CourierFanLayout.center(offset: offset, size: size, side: .left)
        let right = CourierFanLayout.center(offset: offset, size: size, side: .right)
        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(left))
        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(right))
        XCTAssertEqual(left.x + right.x, size.width, accuracy: 0.001)
        XCTAssertEqual(left.y, right.y)
      }
    }
  }

  func testDialWheelCoalescesTrackpadDeltasIntoBoundedDetents() {
    var wheel = CourierDialScroll()
    XCTAssertEqual(wheel.steps(delta: -12), 0)
    XCTAssertEqual(wheel.steps(delta: -12), 0)
    XCTAssertEqual(wheel.steps(delta: -12), 1)
    XCTAssertEqual(wheel.steps(delta: 36), -1)
    XCTAssertEqual(wheel.steps(delta: -.infinity), 0)
    XCTAssertEqual(wheel.steps(delta: -10000), 3)
  }

  func testDialLoopsBothWaysWithoutDuplicatingCardsIncludingTinyAndHugeParcels() {
    XCTAssertEqual(CourierFanLayout.wrappedIndex(6, count: 6), 0)
    XCTAssertEqual(CourierFanLayout.wrappedIndex(-1, count: 6), 5)
    XCTAssertEqual(CourierFanLayout.wrappedIndex(100, count: 0), 0)
    for count in [1, 2, 3, 4, 5, 6, 7, 10000] {
      for index in [-100, -1, 0, count - 1, count, count + 100] {
        let slots = CourierFanLayout.slots(index: index, count: count)
        XCTAssertEqual(slots.count, min(7, count))
        XCTAssertEqual(Set(slots.map(\.index)).count, slots.count)
        XCTAssertTrue(slots.allSatisfy { (0..<count).contains($0.index) })
        XCTAssertEqual(slots.first(where: { $0.offset == 0 })?.index, CourierFanLayout.wrappedIndex(index, count: count))
      }
    }
  }

  func testNewOptionAlwaysSitsBelowRightRegardlessOfFileViewDirection() throws {
    for screen in [CGRect(x: 0, y: 0, width: 640, height: 480), CGRect(x: -1400, y: -200, width: 1400, height: 900)] {
      for origin in [CGPoint(x: screen.minX + 8, y: screen.minY + 8), CGPoint(x: screen.maxX - 112, y: screen.maxY - 136)] {
        let placement = CourierSideLayout.newOptionPlacement(courier: CGRect(origin: origin, size: CourierLayout.compactSize), screen: screen)
        let pane = try XCTUnwrap(placement.pane)
        XCTAssertGreaterThan(pane.minX, placement.courier.maxX)
        XCTAssertLessThan(pane.maxY, placement.courier.minY)
        XCTAssertTrue(screen.contains(placement.frame))
      }
    }
  }

  func testMainPinIsNeverDuplicatedAmongTheSingleRecentSideOption() {
    var pinned = ParcelBox(name: "Main")
    pinned.isPinned = true
    pinned.updatedAt = Date(timeIntervalSince1970: 1)
    var recent = ParcelBox(name: "Recent")
    recent.updatedAt = Date(timeIntervalSince1970: 20)
    var older = ParcelBox(name: "Older")
    older.updatedAt = Date(timeIntervalSince1970: 10)
    XCTAssertEqual(ShelfRanking.primary([older, recent, pinned])?.id, pinned.id)
    XCTAssertEqual(ShelfRanking.sideRecent([older, recent, pinned]).map(\.id), [recent.id])
    XCTAssertEqual(ShelfRanking.primary([older, recent])?.id, recent.id)
    XCTAssertEqual(ShelfRanking.sideRecent([older, recent]).map(\.id), [older.id])
    XCTAssertTrue(ShelfRanking.sideRecent([pinned]).isEmpty)
    XCTAssertNil(ShelfRanking.primary([]))
    XCTAssertTrue(ShelfRanking.sideRecent([]).isEmpty)
  }

  func testAdjustableIconSizingAlwaysReservesLargeControlsAndRejectsInvalidValues() {
    for value: CGFloat in [-20, 64, 88, 128, 10000, .infinity, .nan] {
      let icon = CourierLayout.boundedIconSize(value)
      let size = CourierLayout.courierSize(iconSize: value)
      XCTAssertTrue((64...128).contains(icon))
      XCTAssertGreaterThanOrEqual(size.width, CourierLayout.controlSize * 2 + 24)
      XCTAssertGreaterThanOrEqual(size.height, icon + CourierLayout.controlSize)
      XCTAssertTrue(size.width.isFinite && size.height.isFinite)
    }
  }

  func testCompactShelfSizesGrowOnlyForVisibleContentsAndBoundLongLists() {
    XCTAssertEqual(CourierLayout.compactSize, CGSize(width: 104, height: 128))
    XCTAssertEqual(CourierLayout.chooserSize, CGSize(width: 320, height: 216))
    let one = CourierLayout.contentsSize(itemCount: 1, packed: false, showStatus: false)
    let many = CourierLayout.contentsSize(itemCount: 2000, packed: false, showStatus: false)
    XCTAssertEqual(one.height, 312)
    XCTAssertEqual(many.height, 384)
    XCTAssertEqual(CourierLayout.contentsSize(itemCount: 0, packed: false, showStatus: false), one)
    XCTAssertEqual(CourierLayout.contentsSize(itemCount: 2000, packed: true, showStatus: true),
                   CourierLayout.expandedSize)
    let screen = CGRect(x: -900, y: -500, width: 900, height: 700)
    let anchor = CGPoint(x: -30, y: 170)
    let chooser = CourierLayout.frame(topRight: anchor, screen: screen, expanded: true, showingContents: false)
    let contents = CourierLayout.frame(topRight: anchor, screen: screen, expanded: true, requestedSize: one)
    XCTAssertEqual(chooser.maxX, contents.maxX)
    XCTAssertEqual(chooser.maxY, contents.maxY)
    XCTAssertEqual(chooser.height, 216)
    XCTAssertEqual(contents.height, 312)
  }

  func testFourWayPlacementHonorsDirectionAtEveryDisplayEdge() throws {
    let screen = CGRect(x: -1400, y: -200, width: 1400, height: 900)
    for side in CourierSide.allCases {
      let courier = CGRect(x: -750, y: 120, width: 76.8, height: 81.6)
      let result = CourierSideLayout.placement(courier: courier, screen: screen, pane: CourierSideLayout.folder, side: side)
      let pane = try XCTUnwrap(result.pane)
      XCTAssertEqual(result.side, side)
      switch side {
      case .left: XCTAssertLessThan(pane.maxX, result.courier.minX)
      case .right: XCTAssertGreaterThan(pane.minX, result.courier.maxX)
      case .top: XCTAssertGreaterThan(pane.minY, result.courier.maxY)
      case .bottom: XCTAssertLessThan(pane.maxY, result.courier.minY)
      }
      XCTAssertTrue(screen.contains(result.frame))
    }
    let nearLeft = CGRect(x: screen.minX + 12, y: screen.minY + 12, width: 76.8, height: 81.6)
    let fallback = CourierSideLayout.placement(courier: nearLeft, screen: screen, pane: CourierSideLayout.folder, side: .left)
    XCTAssertEqual(fallback.side, .left)
    XCTAssertTrue(screen.contains(fallback.frame))
    let idle = CourierSideLayout.placement(courier: nearLeft, screen: screen, pane: nil, side: .left)
    XCTAssertNil(idle.pane)
    XCTAssertEqual(idle.frame, nearLeft)
    let narrow = CGRect(x: 0, y: 0, width: 640, height: 480)
    let centered = CGRect(x: 280, y: 200, width: 76.8, height: 81.6)
    let compact = CourierSideLayout.placement(courier: centered, screen: narrow, pane: CourierSideLayout.folder, side: .left)
    XCTAssertTrue(narrow.contains(compact.frame))
    for display in [screen, narrow, CGRect(x: -1920, y: -1080, width: 1920, height: 1056)] {
      for side in CourierSide.allCases {
        for icon: CGFloat in [64, 88, 128] {
          let size = CourierLayout.courierSize(iconSize: icon, closeScale: 1.75, expandScale: 1.75)
          for horizontal in [display.minX + 8, display.midX, display.maxX - size.width - 8] {
            for vertical in [display.minY + 8, display.midY, display.maxY - size.height - 8] {
              let courier = CGRect(origin: CGPoint(x: horizontal, y: vertical), size: size)
              let placement = CourierSideLayout.placement(courier: courier, screen: display, pane: CourierSideLayout.fan, side: side)
              let pane = try XCTUnwrap(placement.pane)
              XCTAssertEqual(placement.side, side)
              XCTAssertTrue(display.contains(placement.frame), "\(display) \(side) \(placement.frame)")
              XCTAssertFalse(pane.intersects(placement.courier))
              XCTAssertEqual(placement.courier.size, courier.size)
            }
          }
        }
      }
    }
  }

  func testVerticalFansMirrorAndKeepUprightCardCentersInsideThePane() {
    for count in [1, 2, 3, 10] {
      let size = CGSize(width: 544, height: 270)
      for offset in -2...2 {
        let top = CourierFanLayout.center(offset: offset, size: size, side: .top, count: count)
        let bottom = CourierFanLayout.center(offset: offset, size: size, side: .bottom, count: count)
        XCTAssertEqual(top.x, bottom.x)
        XCTAssertEqual(top.y + bottom.y, size.height, accuracy: 0.001)
        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(top))
        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(bottom))
      }
    }
  }

  func testPinMigrationKeepsOnlyFirstRankedPinWithoutChangingPieceRetention() {
    var first = ParcelBox(name: "First")
    first.isPinned = true; first.updatedAt = Date(timeIntervalSince1970: 10)
    var second = ParcelBox(name: "Legacy")
    second.items = [ParcelItem(sourcePath: "/fixture", displayName: "Fixture", isPinned: true)]
    second.updatedAt = Date(timeIntervalSince1970: 5)
    let migrated = ShelfRanking.normalizePins([second, first])
    XCTAssertEqual(migrated.filter(\.isShelfPinned).map(\.id), [first.id])
    XCTAssertTrue(migrated[0].items[0].isPinned)
  }

  func testExplicitParcelPinOverridesLegacyPieceRankingAndSurvivesCoding() throws {
    var box = ParcelBox(name: "Legacy")
    box.items = [ParcelItem(sourcePath: "/one", displayName: "one", isPinned: true)]
    XCTAssertTrue(box.isShelfPinned)
    box.isPinned = false
    XCTAssertFalse(box.isShelfPinned)
    let restored = try JSONDecoder().decode(ParcelBox.self, from: JSONEncoder().encode(box))
    XCTAssertFalse(restored.isShelfPinned)
    XCTAssertTrue(restored.items[0].isPinned)
    var empty = ParcelBox(name: "Pinned empty bag")
    empty.isPinned = true
    XCTAssertEqual(ShelfRanking.destinations([box, empty]).first?.id, empty.id)
  }

  func testExpansionKeepsAvatarAnchorAndFitsDisplaysIncludingNegativeOrigins() {
    let screens = [CGRect(x: 0, y: 24, width: 1440, height: 876),
                   CGRect(x: -1920, y: -1080, width: 1920, height: 1056),
                   CGRect(x: 100, y: 100, width: 800, height: 500)]
    for screen in screens {
      for anchor in [CGPoint(x: screen.minX, y: screen.minY),
                     CGPoint(x: screen.maxX + 200, y: screen.maxY + 200)] {
        let small = CourierLayout.frame(topRight: anchor, screen: screen, expanded: false)
        let large = CourierLayout.frame(topRight: anchor, screen: screen, expanded: true)
        XCTAssertEqual(small.maxX, large.maxX)
        XCTAssertEqual(small.maxY, large.maxY)
        XCTAssertTrue(screen.contains(small))
        XCTAssertTrue(screen.contains(large))
      }
    }
  }

  func testRanksPinnedBeforeRecentAndKeepsTiesStable() {
    var olderPinned = ParcelBox(name: "Pinned older")
    olderPinned.updatedAt = Date(timeIntervalSince1970: 1)
    olderPinned.items = [ParcelItem(sourcePath: "/one", displayName: "one", isPinned: true)]
    var newerPinned = olderPinned
    newerPinned.id = UUID()
    newerPinned.name = "Pinned newer"
    newerPinned.updatedAt = Date(timeIntervalSince1970: 2)
    var recent = ParcelBox(name: "Recent")
    recent.updatedAt = Date(timeIntervalSince1970: 10)
    var tied = recent
    tied.id = UUID()
    tied.name = "Tied"
    var oldest = ParcelBox(name: "Oldest")
    oldest.updatedAt = .distantPast
    let boxes = [recent, olderPinned, newerPinned, tied, oldest]
    XCTAssertEqual(ShelfRanking.destinations(boxes).map(\.name),
                   ["Pinned newer", "Pinned older", "Recent", "Tied"])
    XCTAssertTrue(ShelfRanking.destinations(boxes, limit: 0).isEmpty)
  }

  func testStalePasteboardDoesNotTurnTextSelectionIntoAFileDrag() {
    var session = ExternalDragSession(pasteboardGeneration: 7)
    session.update(buttonDown: true, pasteboardGeneration: 7, supported: true)
    XCTAssertFalse(session.isDragging)
    session.update(buttonDown: true, pasteboardGeneration: 8, supported: false)
    XCTAssertFalse(session.isDragging)
    session.update(buttonDown: true, pasteboardGeneration: 8, supported: true)
    XCTAssertTrue(session.isDragging)
    session.update(buttonDown: true, pasteboardGeneration: 8, supported: true)
    XCTAssertTrue(session.isDragging)
    session.update(buttonDown: false, pasteboardGeneration: 8, supported: true)
    XCTAssertFalse(session.isDragging)
    session.update(buttonDown: true, pasteboardGeneration: 8, supported: true)
    XCTAssertFalse(session.isDragging)
  }

  func testOwnDragSuppressionResetsAfterMouseRelease() {
    var session = ExternalDragSession(pasteboardGeneration: 1)
    session.suppress()
    session.update(buttonDown: true, pasteboardGeneration: 2, supported: true)
    XCTAssertFalse(session.isDragging)
    session.update(buttonDown: false, pasteboardGeneration: 2, supported: true)
    session.update(buttonDown: true, pasteboardGeneration: 3, supported: true)
    XCTAssertTrue(session.isDragging)
  }
}

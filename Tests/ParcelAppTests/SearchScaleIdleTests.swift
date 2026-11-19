import AppKit
import ParcelCore
import XCTest
@testable import ParcelApp

final class SearchScaleIdleTests: XCTestCase {
  @MainActor func testUniversalScalePersistsAndKeepsPhysicalCloseAndNewTargetsLarge() throws {
    let name = "ParcelUniversalScale-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store, defaults: defaults)
    for scale: CGFloat in [0.75, 1, 1.5] {
      shelf.interfaceScale = scale
      XCTAssertGreaterThanOrEqual(shelf.closeControlSize * scale, 32)
      XCTAssertGreaterThanOrEqual(shelf.expandControlSize * scale, 32)
      XCTAssertEqual(shelf.logicalArrangement.frame.width * scale, shelf.arrangement.frame.width, accuracy: 0.001)
      for side in CourierSide.allCases {
        shelf.side = side; shelf.select(try XCTUnwrap(store.selectedBox))
        XCTAssertEqual(shelf.arrangement.side, side)
      }
    }
    XCTAssertEqual(DropPopupController(store: store, defaults: defaults).interfaceScale, 1.5)
    shelf.interfaceScale = .nan
    XCTAssertEqual(shelf.interfaceScale, 1)
  }
  @MainActor func testNaturalSearchFiltersHubAndCurrentParcelAndClearResetsAllFilters() throws {
    let store = ParcelStore(persist: false)
    store.boxes[0].items = [ParcelItem(sourcePath: "/Budget.xlsx", displayName: "Budget.xlsx", byteCount: 20_000_000),
      ParcelItem(sourcePath: "/Notes.txt", displayName: "Notes.txt")]
    store.searchText = "all excel files over 10 MB"
    XCTAssertEqual(store.filteredItems.map(\.effectiveName), ["Budget.xlsx"])
    XCTAssertEqual(store.filteredBoxes.count, 1)
    store.fileTypeFilter = .pdf
    XCTAssertTrue(store.filteredItems.isEmpty)
    store.clearFileSearch()
    XCTAssertEqual(store.filteredItems.count, 2)
    XCTAssertFalse(store.isSearching)
  }
  @MainActor func testIdlePreferencePersistsWhileIslandRemainsVisibleAndCollapsed() async throws {
    let name = "ParcelIdle-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store, defaults: defaults)
    XCTAssertEqual(shelf.idleTimeout, 30)
    shelf.idleTimeout = 0
    shelf.restoreResident()
    try await Task.sleep(for: .milliseconds(80))
    XCTAssertTrue(shelf.parkedInMenuBar)
    XCTAssertTrue(shelf.isVisible)
    XCTAssertFalse(shelf.expanded)
    XCTAssertEqual(DropPopupController(store: store, defaults: defaults).idleTimeout, 0)
    shelf.idleTimeout = 5
    XCTAssertEqual(DropPopupController(store: store, defaults: defaults).idleTimeout, 5)
    shelf.idleTimeout = 10000
    XCTAssertEqual(shelf.idleTimeout, 3600)
  }
  @MainActor func testIncomingDragOpensTopNotchWithoutRestoringFloatingCourier() throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    shelf.viewStyle = .dial
    shelf.restoreResident()
    XCTAssertTrue(shelf.parkedInMenuBar)
    shelf.showForDrag()
    XCTAssertTrue(shelf.parkedInMenuBar)
    XCTAssertTrue(shelf.isVisible)
    XCTAssertTrue(shelf.toolsVisible)
    XCTAssertEqual(shelf.activeModule, .parcel)
    let screen = try XCTUnwrap(NSScreen.main).frame
    XCTAssertEqual(shelf.arrangement.frame.height, 174, accuracy: 0.5)
    XCTAssertEqual(shelf.arrangement.frame.midX, screen.midX, accuracy: 0.5)
    XCTAssertEqual(shelf.arrangement.frame.maxY, screen.maxY, accuracy: 0.5)
    XCTAssertEqual(shelf.arrangement.frame.width, min(390, max(350, screen.width * 0.20)), accuracy: 0.5)
    XCTAssertLessThan(shelf.arrangement.frame.height, shelf.arrangement.frame.width * 0.5)
    XCTAssertLessThanOrEqual(shelf.arrangement.frame.width, screen.width * 0.4)
    XCTAssertLessThanOrEqual(shelf.arrangement.frame.height, screen.height * 0.4)
    shelf.parkInMenuBar()
  }
  @MainActor func testParkedViewStylesUseDistinctCompactGeometryAtThePhysicalTopEdge() throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    shelf.restoreResident(); shelf.showForDrag()
    let screen = try XCTUnwrap(NSScreen.main).frame
    shelf.viewStyle = .dial
    let dial = shelf.arrangement.frame
    shelf.viewStyle = .grid
    let grid = shelf.arrangement.frame
    shelf.viewStyle = .list
    let list = shelf.arrangement.frame
    XCTAssertEqual(dial.maxY, screen.maxY, accuracy: 0.5)
    XCTAssertEqual(grid.maxY, screen.maxY, accuracy: 0.5)
    XCTAssertEqual(list.maxY, screen.maxY, accuracy: 0.5)
    XCTAssertLessThan(dial.height, grid.height)
    XCTAssertLessThan(list.width, grid.width)
  }
  @MainActor func testCancellingSearchRestoresItemsWithoutDeletingAnything() throws {
    let store = ParcelStore(persist: false)
    store.boxes[0].items = [ParcelItem(sourcePath: "/Budget.xlsx", displayName: "Budget.xlsx"),
      ParcelItem(sourcePath: "/Notes.txt", displayName: "Notes.txt")]
    let shelf = DropPopupController(store: store)
    store.searchText = "missing"
    XCTAssertTrue(store.filteredItems.isEmpty)
    shelf.hideSearch(clear: true)
    XCTAssertEqual(store.filteredItems.count, 2)
    XCTAssertEqual(store.items.count, 2)
  }
  @MainActor func testPersistentIslandExpandsIntoFilesAndCollapsesInsteadOfDisappearing() throws {
    let name = "ParcelIsland-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store, defaults: defaults, folderHoverDelay: 0)
    shelf.restoreResident()
    XCTAssertTrue(shelf.isVisible)
    XCTAssertFalse(shelf.expanded)
    XCTAssertGreaterThanOrEqual(shelf.arrangement.frame.size.width, 170)
    XCTAssertLessThanOrEqual(shelf.arrangement.frame.size.width, 260)
    shelf.courierHoverChanged(true)
    XCTAssertTrue(shelf.expanded)
    XCTAssertTrue(shelf.toolsVisible)
    XCTAssertEqual(shelf.activeModule, .dashboard)
    shelf.dismiss()
    XCTAssertTrue(shelf.isVisible)
    XCTAssertFalse(shelf.expanded)
    shelf.isPersistent = false
    XCTAssertFalse(shelf.isVisible)
  }
  @MainActor func testCopyMatchingFilesExcludesHiddenResultsAndPreservesClipboardOnMissingSource() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("Budget.xlsx")
    let second = root.appendingPathComponent("Notes.txt")
    try "Spreadsheet fixture".write(to: first, atomically: true, encoding: .utf8)
    try "Text fixture".write(to: second, atomically: true, encoding: .utf8)
    let store = ParcelStore(persist: false)
    store.ingest([first, second]); store.searchText = "excel files"
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    XCTAssertEqual(try store.copyShelfFiles(in: XCTUnwrap(store.selectedBox), to: board, matchingSearch: true), 1)
    let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    XCTAssertEqual(urls, [first])
    store.boxes[0].items.append(ParcelItem(sourcePath: "/missing/Budget.xlsx", displayName: "Budget.xlsx"))
    XCTAssertThrowsError(try store.copyShelfFiles(in: XCTUnwrap(store.selectedBox), to: board, matchingSearch: true))
    XCTAssertEqual(board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], [first])
  }
}

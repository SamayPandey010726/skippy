import AppKit
import Combine
import ParcelCore
import XCTest
@testable import ParcelApp

final class CourierInteractionTests: XCTestCase {
  @MainActor func testDragAndButtonSurfacesAcceptTheFirstClickInInactivePanels() {
    XCTAssertTrue(DragOutSurface.SendingView().acceptsFirstMouse(for: nil))
    XCTAssertTrue(FileDropSurface.ReceivingView().acceptsFirstMouse(for: nil))
  }
  @MainActor func testPackedParcelCopiesAsOneZip() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let zip = root.appendingPathComponent("Packed parcel.zip")
    try Data("zip fixture".utf8).write(to: zip)
    let store = ParcelStore(persist: false)
    store.archiveURL = zip; store.phase = .ready
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    XCTAssertTrue(store.copyArchiveToClipboard(to: board))
    let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    XCTAssertEqual(urls, [zip])
  }
  @MainActor func testAvatarMovementUsesOriginalMouseDownWithoutStartingAFileDrag() throws {
    let surface = DragOutSurface.SendingView()
    let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
      location: CGPoint(x: 10, y: 10), modifierFlags: [], timestamp: 1, windowNumber: 0,
      context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    let dragged = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDragged,
      location: CGPoint(x: 30, y: 30), modifierFlags: [], timestamp: 2, windowNumber: 0,
      context: nil, eventNumber: 2, clickCount: 1, pressure: 1))
    var beginnings = 0
    var endings = 0
    var clicks = 0
    var moveEvents: [NSEvent] = []
    surface.windowMovement = WindowMoveActions(begin: { beginnings += 1 },
      drag: { moveEvents.append($0) }, end: { endings += 1 })
    surface.tap = { clicks += 1 }
    surface.mouseDown(with: down)
    surface.mouseUp(with: down)
    XCTAssertEqual(clicks, 1)
    XCTAssertTrue(moveEvents.isEmpty)
    surface.mouseDown(with: down)
    surface.mouseDragged(with: dragged)
    surface.mouseDragged(with: dragged)
    surface.mouseUp(with: dragged)
    XCTAssertEqual(moveEvents.count, 1)
    XCTAssertTrue(moveEvents.first === down)
    XCTAssertEqual(clicks, 1)
    XCTAssertEqual(beginnings, 2)
    XCTAssertEqual(endings, 2)
  }

  @MainActor func testMovingCancelsPendingHoverAndDefersShelfChanges() async throws {
    let name = "ParcelNativeMove-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store, defaults: defaults, hoverDelay: 0.08)
    shelf.dragHoverChanged(true)
    shelf.beginPopupMove()
    shelf.dragHoverChanged(true)
    shelf.expand()
    try await Task.sleep(for: .milliseconds(130))
    XCTAssertFalse(shelf.expanded)
    shelf.finishPopupMove()
    shelf.hoverChanged(false)
    shelf.dragHoverChanged(true)
    try await Task.sleep(for: .milliseconds(130))
    XCTAssertTrue(shelf.expanded)
    shelf.beginPopupMove()
    shelf.dismiss()
    XCTAssertTrue(shelf.expanded)
    shelf.finishPopupMove()
    shelf.dismiss()
    XCTAssertFalse(shelf.expanded)
  }

  @MainActor func testBatchIntakePublishesOnceAndDeduplicatesWithinTheBatch() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let files = try (0..<24).map { index in
      let file = folder.appendingPathComponent("Piece-\(index).txt")
      try "Fixture".write(to: file, atomically: true, encoding: .utf8)
      return file
    }
    let store = ParcelStore(persist: false)
    var publications = 0
    let observation = store.$boxes.dropFirst().sink { _ in publications += 1 }
    store.ingest(files + files)
    XCTAssertEqual(store.items.count, 24)
    XCTAssertEqual(publications, 1)
    XCTAssertEqual(store.bounce, 1)
    store.ingest(files)
    XCTAssertEqual(publications, 1)
    withExtendedLifetime(observation) {}
  }

  @MainActor func testWorkbenchRequiresExplicitPostLaunchReopen() {
    XCTAssertFalse(ParcelAppDelegate.shouldOpenWorkbench(launchFinished: false, isExplicitReopen: true))
    XCTAssertFalse(ParcelAppDelegate.shouldOpenWorkbench(launchFinished: true, isExplicitReopen: false))
    XCTAssertFalse(ParcelAppDelegate.shouldOpenWorkbench(launchFinished: true, isExplicitReopen: true))
    XCTAssertFalse(ParcelAppDelegate.shouldSummonShelf(secondsSinceLaunch: 0.2))
    XCTAssertTrue(ParcelAppDelegate.shouldSummonShelf(secondsSinceLaunch: 1.1))
  }

  @MainActor func testBriefHoverCancelsAndLeavingCollapsesPromptly() async throws {
    let name = "ParcelCompactHover-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(true, forKey: "parcel.persistentCourier")
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store, defaults: defaults, hoverDelay: 0.08)
    shelf.dragHoverChanged(true)
    shelf.hoverChanged(false)
    try await Task.sleep(for: .milliseconds(130))
    XCTAssertFalse(shelf.expanded)
    shelf.dragHoverChanged(true)
    try await Task.sleep(for: .milliseconds(130))
    XCTAssertTrue(shelf.expanded)
    XCTAssertEqual(shelf.arrangement.pane?.size, CourierSideLayout.choices)
    shelf.select(try XCTUnwrap(store.selectedBox))
    XCTAssertLessThan(try XCTUnwrap(shelf.arrangement.pane).height, CourierSideLayout.fan.height)
    XCTAssertTrue(try XCTUnwrap(shelf.arrangement.pane).contains(shelf.arrangement.courier))
    shelf.hoverChanged(false)
    try await Task.sleep(for: .milliseconds(550))
    XCTAssertFalse(shelf.expanded)
    XCTAssertEqual(shelf.contentSize, CourierLayout.compactSize)
  }

  @MainActor func testNativeCopyWritesFileURLsAndInvalidInputPreservesClipboard() throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    guard board.setString("Clipboard fixture", forType: .string) else {
      throw XCTSkip("The macOS pasteboard service is unavailable.")
    }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try "Original stays safe".write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    let store = ParcelStore(persist: false)
    let id = try XCTUnwrap(store.selectedBox)
    store.boxes[0].items = [ParcelItem(sourcePath: file.path, displayName: "Original")]
    XCTAssertEqual(try store.copyShelfFiles(in: id, to: board), 1)
    let copied = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    XCTAssertEqual(copied, [file])
    store.boxes[0].items.append(ParcelItem(sourcePath: "/missing-courier-copy-fixture", displayName: "Missing"))
    board.clearContents()
    XCTAssertTrue(board.setString("Keep this clipboard", forType: .string))
    XCTAssertThrowsError(try store.copyShelfFiles(in: id, to: board))
    XCTAssertEqual(board.string(forType: .string), "Keep this clipboard")
    XCTAssertEqual(try String(contentsOf: file), "Original stays safe")
  }

  @MainActor func testRestoreCollisionKeepsRecoverableBinEntry() throws {
    let store = ParcelStore(persist: false)
    let original = try XCTUnwrap(store.current)
    store.moveToBin(original.id)
    store.boxes.append(original)
    let before = store.trashedBoxes
    store.restoreFromBin(original.id)
    XCTAssertEqual(store.trashedBoxes, before)
    XCTAssertEqual(store.boxes.filter { $0.id == original.id }.count, 1)
    XCTAssertTrue(store.error?.contains("kept unchanged") == true)
  }

  @MainActor func testReopeningInHubStillInvalidatesPossiblyStaleArchive() throws {
    let store = ParcelStore(persist: false)
    store.archiveURL = URL(fileURLWithPath: "/test.zip")
    store.phase = .ready
    store.selectBox(try XCTUnwrap(store.selectedBox))
    XCTAssertNil(store.archiveURL)
    XCTAssertEqual(store.phase, .open)
  }

  @MainActor func testSummonAndCollapseCannotInterruptPackingOrReception() throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    let id = try XCTUnwrap(store.selectedBox)
    shelf.select(id)
    store.phase = .packing
    shelf.summon()
    shelf.dismiss()
    XCTAssertEqual(shelf.focusedBox, id)
    XCTAssertTrue(shelf.expanded)
    store.phase = .open
    store.beginReceiving()
    shelf.moveToBin(id)
    XCTAssertTrue(store.trashedBoxes.isEmpty)
    shelf.dismiss()
    XCTAssertTrue(shelf.expanded)
    store.endReceiving()
  }

  @MainActor func testExpiredBinEntryCannotBeRestoredAndDoesNotResetCurrentArchive() throws {
    let store = ParcelStore(persist: false)
    let removed = try XCTUnwrap(store.selectedBox)
    let current = try XCTUnwrap(store.shelfDestination(nil))
    let deleted = Date()
    store.moveToBin(removed, now: deleted)
    store.archiveURL = URL(fileURLWithPath: "/test.zip")
    store.phase = .ready
    store.restoreFromBin(removed, now: deleted.addingTimeInterval(30 * 86400))
    XCTAssertTrue(store.trashedBoxes.isEmpty)
    XCTAssertFalse(store.boxes.contains { $0.id == removed })
    XCTAssertEqual(store.selectedBox, current)
    XCTAssertEqual(store.archiveURL?.lastPathComponent, "test.zip")
    XCTAssertEqual(store.phase, .ready)
  }

  @MainActor func testDirectPinDoesNotChangePieceRetentionOrInvalidateArchive() throws {
    let store = ParcelStore(persist: false)
    let id = try XCTUnwrap(store.selectedBox)
    store.boxes[0].items = [ParcelItem(sourcePath: "/one", displayName: "One")]
    let archive = URL(fileURLWithPath: "/test.zip")
    store.archiveURL = archive
    store.phase = .ready
    let updated = store.boxes[0].updatedAt
    store.toggleParcelPin(id)
    XCTAssertTrue(store.boxes[0].isShelfPinned)
    XCTAssertFalse(store.boxes[0].items[0].isPinned)
    XCTAssertEqual(store.archiveURL, archive)
    XCTAssertEqual(store.boxes[0].updatedAt, updated)
    store.toggleParcelPin(id)
    XCTAssertFalse(store.boxes[0].isShelfPinned)
  }

  @MainActor func testRepeatedPreviewSelectionKeepsReadyArchiveAndDoesNotCreateWindows() throws {
    let before = NSApplication.shared.windows.count
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    let id = try XCTUnwrap(store.selectedBox)
    let archive = URL(fileURLWithPath: "/test.zip")
    store.archiveURL = archive
    store.phase = .ready
    shelf.select(id)
    shelf.select(id)
    XCTAssertEqual(store.archiveURL, archive)
    XCTAssertEqual(store.phase, .ready)
    XCTAssertEqual(NSApplication.shared.windows.count, before)
  }

  @MainActor func testCancelledHoverNeverSelectsAnOldBag() async throws {
    let store = ParcelStore(persist: false)
    let first = try XCTUnwrap(store.selectedBox)
    let second = try XCTUnwrap(store.shelfDestination(nil))
    let shelf = DropPopupController(store: store)
    shelf.preview(first, hovering: true)
    shelf.preview(second, hovering: true)
    shelf.preview(first, hovering: false)
    try await Task.sleep(for: .milliseconds(220))
    XCTAssertNil(shelf.focusedBox)
    shelf.select(second)
    XCTAssertTrue(shelf.showingFolder)
    shelf.preview(first, hovering: true)
    shelf.preview(first, hovering: false)
    try await Task.sleep(for: .milliseconds(220))
    XCTAssertEqual(shelf.focusedBox, second)
  }

  @MainActor func testCopyResolutionIsAllOrNothingAndUsesPreparedCopies() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("prepared.txt")
    try "prepared".write(to: file, atomically: true, encoding: .utf8)
    let store = ParcelStore(persist: false)
    let id = try XCTUnwrap(store.selectedBox)
    var item = ParcelItem(sourcePath: "/missing/original", displayName: "Original")
    item.preparedPath = file.path
    store.boxes[0].items = [item]
    XCTAssertEqual(try store.shelfFileURLs(in: id), [file])
    XCTAssertThrowsError(try store.shelfFileURLs(in: id, itemID: UUID()))
    store.boxes[0].items.append(ParcelItem(sourcePath: "/missing/second", displayName: "Missing"))
    XCTAssertThrowsError(try store.shelfFileURLs(in: id))
    XCTAssertEqual(try store.shelfFileURLs(in: id, itemID: item.id), [file])
    XCTAssertEqual(try String(contentsOf: file), "prepared")
  }

  @MainActor func testCollapseCancelsPendingPreviewAndPreservesLibrary() async throws {
    let name = "ParcelCourierTests-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(true, forKey: "parcel.persistentCourier")
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store, defaults: defaults)
    shelf.expand()
    shelf.preview(try XCTUnwrap(store.selectedBox), hovering: true)
    let before = store.boxes
    shelf.dismiss()
    try await Task.sleep(for: .milliseconds(220))
    XCTAssertFalse(shelf.expanded)
    XCTAssertNil(shelf.focusedBox)
    XCTAssertEqual(store.boxes, before)
  }

  @MainActor func testBinRestoreAndExpiryNeverDeleteOriginals() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try "original".write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    let store = ParcelStore(persist: false)
    let id = try XCTUnwrap(store.selectedBox)
    store.boxes[0].items = [ParcelItem(sourcePath: file.path, displayName: "Original")]
    store.boxes[0].note = "A note"
    store.toggleParcelPin(id)
    let original = store.boxes[0]
    let deleted = Date()
    store.moveToBin(id, now: deleted)
    XCTAssertFalse(store.boxes.contains { $0.id == id })
    XCTAssertEqual(store.trashedBoxes.first?.box, original)
    store.purgeExpiredBin(now: deleted.addingTimeInterval(30 * 86400 - 1))
    XCTAssertEqual(store.trashedBoxes.count, 1)
    store.restoreFromBin(id)
    XCTAssertTrue(store.trashedBoxes.isEmpty)
    XCTAssertEqual(store.current, original)
    store.moveToBin(id, now: deleted)
    store.purgeExpiredBin(now: deleted.addingTimeInterval(30 * 86400))
    XCTAssertTrue(store.trashedBoxes.isEmpty)
    XCTAssertEqual(try String(contentsOf: file), "original")
  }

  @MainActor func testBinRejectsBusyChangesAndCanEmptyOneOrAll() throws {
    let store = ParcelStore(persist: false)
    let first = try XCTUnwrap(store.selectedBox)
    let second = try XCTUnwrap(store.shelfDestination(nil))
    store.phase = .packing
    store.moveToBin(first)
    XCTAssertTrue(store.trashedBoxes.isEmpty)
    store.phase = .open
    store.moveToBin(first)
    store.moveToBin(second)
    XCTAssertEqual(store.trashedBoxes.count, 2)
    store.emptyBin(first)
    XCTAssertEqual(store.trashedBoxes.map(\.id), [second])
    store.emptyBin()
    XCTAssertTrue(store.trashedBoxes.isEmpty)
    XCTAssertFalse(store.boxes.isEmpty)
    XCTAssertNotNil(store.current)
  }
}

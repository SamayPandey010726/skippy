import AppKit
import Combine
import ParcelCore
import XCTest
@testable import ParcelApp

final class SideCourierTests: XCTestCase {
  @MainActor func testIndependentControlPreferencesAndDefaultDirectDialPersist() throws {
    let name = "CourierControlSizing-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store, defaults: defaults)
    XCTAssertEqual(shelf.viewStyle, .dial)
    shelf.iconSize = 128
    shelf.closeControlScale = 1.5
    shelf.expandControlScale = 0.8
    let restored = DropPopupController(store: store, defaults: defaults)
    XCTAssertEqual(restored.closeControlScale, 1.5)
    XCTAssertEqual(restored.expandControlScale, 0.8)
    XCTAssertGreaterThan(restored.closeControlSize, restored.expandControlSize)
    XCTAssertGreaterThanOrEqual(restored.courierSize.width, restored.closeControlSize + restored.expandControlSize + 24)
  }

  @MainActor func testPrimaryDropCatchesOnlyAcceptedFilesWithoutPoppingTheDialOrReplayingDuplicates() throws {
    let name = "CourierReceipt-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store, defaults: defaults)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
    try "Receipt fixture".write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    let receipt = try XCTUnwrap(shelf.beginPrimaryDrop())
    XCTAssertFalse(shelf.showingFolder)
    receipt.receive([file])
    XCTAssertEqual(shelf.intakeEvent, 1)
    XCTAssertEqual(shelf.intakeCount, 1)
    XCTAssertEqual(shelf.intakeBox, shelf.primaryBox?.id)
    receipt.receive([file])
    XCTAssertEqual(shelf.intakeEvent, 1)
    shelf.tapCourier()
    XCTAssertTrue(shelf.controlsVisible)
    XCTAssertFalse(shelf.showingFolder)
  }

  @MainActor func testQueuedRankUpdatesCannotResurrectTheRemovedRecentOption() async throws {
    let store = ParcelStore(persist: false)
    let primary = try XCTUnwrap(store.selectedBox)
    store.toggleParcelPin(primary)
    let recent = try XCTUnwrap(store.shelfDestination(nil))
    let shelf = DropPopupController(store: store)
    shelf.moveToBin(recent)
    var updates: [[UUID]] = []
    let observation = shelf.$destinations.sink { updates.append($0.map(\.id)) }
    try await Task.sleep(for: .milliseconds(80))
    XCTAssertTrue(updates.allSatisfy { !$0.contains(recent) })
    XCTAssertTrue(shelf.destinations.isEmpty)
    withExtendedLifetime(observation) {}
  }

  @MainActor func testInlineConfirmationWaitsForAnExplicitDecision() async throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    shelf.select(try XCTUnwrap(store.selectedBox))
    shelf.confirmationChanged(true)
    shelf.hoverChanged(false)
    try await Task.sleep(for: .milliseconds(550))
    XCTAssertTrue(shelf.expanded)
    shelf.confirmationChanged(false)
    try await Task.sleep(for: .milliseconds(550))
    XCTAssertFalse(shelf.expanded)
  }

  @MainActor func testEmptyHoverDirectlyOpensPinnedFilesAndLeavingCancelsIt() async throws {
    let store = ParcelStore(persist: false)
    let pinned = try XCTUnwrap(store.selectedBox)
    store.toggleParcelPin(pinned)
    let shelf = DropPopupController(store: store, hoverDelay: 0.08, folderHoverDelay: 0.24)
    shelf.courierHoverChanged(true)
    XCTAssertFalse(shelf.expanded)
    XCTAssertFalse(shelf.showingFolder)
    shelf.courierHoverChanged(false)
    try await Task.sleep(for: .milliseconds(310))
    XCTAssertFalse(shelf.showingFolder)
    shelf.courierHoverChanged(true)
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertTrue(shelf.showingFolder)
    XCTAssertEqual(shelf.focusedBox, pinned)
    shelf.dismiss()
  }

  @MainActor func testMovingOrExplicitClickCancelsTheAutomaticFolder() async throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store, hoverDelay: 0.05, folderHoverDelay: 0.18)
    shelf.courierHoverChanged(true)
    shelf.beginPopupMove()
    try await Task.sleep(for: .milliseconds(240))
    XCTAssertFalse(shelf.expanded)
    shelf.finishPopupMove()
    shelf.courierHoverChanged(false)
    shelf.courierHoverChanged(true)
    shelf.tapCourier()
    try await Task.sleep(for: .milliseconds(240))
    XCTAssertFalse(shelf.showingFolder)
    shelf.dismiss()
  }

  @MainActor func testCourierPreferencesPersistAndNeverAddAThirdParcel() throws {
    let name = "CourierPreferences-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ParcelStore(persist: false)
    let pinned = try XCTUnwrap(store.selectedBox)
    store.toggleParcelPin(pinned)
    _ = try XCTUnwrap(store.shelfDestination(nil))
    let shelf = DropPopupController(store: store, defaults: defaults)
    XCTAssertEqual(shelf.primaryBox?.id, pinned)
    XCTAssertTrue(shelf.destinations.isEmpty)
    shelf.iconSize = 120
    shelf.viewStyle = .dial
    let restored = DropPopupController(store: store, defaults: defaults)
    XCTAssertEqual(restored.iconSize, 120)
    XCTAssertEqual(restored.viewStyle, .dial)
    XCTAssertEqual(restored.contentSize, CourierLayout.courierSize(iconSize: 120))
    restored.iconSize = .nan
    XCTAssertEqual(restored.iconSize, CourierLayout.defaultIconSize)
  }

  @MainActor func testNativeMenusSuspendAutoHideUntilAllMenusFinishTracking() async throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    shelf.select(try XCTUnwrap(store.selectedBox))
    let menu = NSMenu()
    let submenu = NSMenu()
    shelf.menuTrackingChanged(menu, active: true)
    shelf.menuTrackingChanged(submenu, active: true)
    shelf.hoverChanged(false)
    try await Task.sleep(for: .milliseconds(550))
    XCTAssertTrue(shelf.expanded)
    shelf.menuTrackingChanged(submenu, active: false)
    try await Task.sleep(for: .milliseconds(550))
    XCTAssertTrue(shelf.expanded)
    shelf.menuTrackingChanged(menu, active: false)
    try await Task.sleep(for: .milliseconds(550))
    XCTAssertFalse(shelf.expanded)
  }

  @MainActor func testBackgroundIntakeKeepsTheOtherParcelsReadyArchive() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
    try "Background fixture".write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    let store = ParcelStore(persist: false)
    let watched = try XCTUnwrap(store.selectedBox)
    _ = try XCTUnwrap(store.shelfDestination(nil))
    let archive = URL(fileURLWithPath: "/unrelated-ready.zip")
    store.archiveURL = archive; store.phase = .ready
    store.ingest([file], into: watched)
    XCTAssertEqual(store.archiveURL, archive)
    XCTAssertEqual(store.phase, .ready)
    XCTAssertEqual(store.boxes.first(where: { $0.id == watched })?.items.count, 1)
  }

  @MainActor func testPrimaryDropUsesPinOtherwiseRecencyWithoutCreatingAnotherParcel() throws {
    let store = ParcelStore(persist: false)
    let first = try XCTUnwrap(store.selectedBox)
    let recent = try XCTUnwrap(store.shelfDestination(nil))
    let shelf = DropPopupController(store: store)
    XCTAssertNotNil(shelf.beginPrimaryDrop())
    XCTAssertEqual(shelf.focusedBox, recent)
    store.toggleParcelPin(first)
    XCTAssertNotNil(shelf.beginPrimaryDrop())
    XCTAssertEqual(shelf.focusedBox, first)
    XCTAssertEqual(store.boxes.count, 2)
  }
  @MainActor func testClickShowsOnlyControlsAndOnlyOneParcelCanBePinned() throws {
    let store = ParcelStore(persist: false)
    let first = try XCTUnwrap(store.selectedBox)
    let second = try XCTUnwrap(store.shelfDestination(nil))
    store.toggleParcelPin(first); store.toggleParcelPin(second)
    XCTAssertEqual(store.boxes.filter(\.isShelfPinned).map(\.id), [second])
    let shelf = DropPopupController(store: store)
    shelf.tapCourier()
    XCTAssertTrue(shelf.controlsVisible)
    XCTAssertFalse(shelf.expanded)
    XCTAssertFalse(shelf.showingFolder)
    shelf.showChoices()
    let placement = shelf.arrangement
    let pane = try XCTUnwrap(placement.pane)
    XCTAssertGreaterThan(pane.minX, placement.courier.maxX)
    XCTAssertLessThan(pane.maxY, placement.courier.minY)
    shelf.select(second)
    XCTAssertTrue(shelf.showingFolder)
    XCTAssertEqual(shelf.focusedBox, second)
    shelf.showChoices()
    XCTAssertFalse(shelf.showingFolder)
    XCTAssertNil(shelf.focusedBox)
    store.moveToBin(second)
    store.toggleParcelPin(first)
    store.restoreFromBin(second)
    XCTAssertEqual(store.boxes.filter(\.isShelfPinned).map(\.id), [first])
  }
  @MainActor func testOneSecondDragHoverDoesNotOpenEarlyAndLeavingCancelsIt() async throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    shelf.dragHoverChanged(true)
    try await Task.sleep(for: .milliseconds(400))
    XCTAssertFalse(shelf.expanded)
    shelf.dragHoverChanged(false)
    try await Task.sleep(for: .milliseconds(800))
    XCTAssertFalse(shelf.expanded)
    shelf.dragHoverChanged(true)
    try await Task.sleep(for: .milliseconds(1100))
    XCTAssertTrue(shelf.expanded)
    XCTAssertFalse(shelf.showingFolder)
    shelf.dismiss()
  }
}

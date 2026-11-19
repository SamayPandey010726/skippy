import AppKit
import ParcelCore
import SwiftUI
import XCTest
@testable import ParcelApp

final class ShelfIntakeTests: XCTestCase {
  @MainActor func testOneNewDestinationForEveryCallbackInADrop() throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    let fixture = try makeFiles()
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    let handler = try XCTUnwrap(shelf.beginDrop(into: nil))
    let destination = try XCTUnwrap(shelf.focusedBox)
    handler.receiving(true)
    XCTAssertNil(shelf.beginDrop(into: nil))
    handler.receive([fixture.first])
    handler.receive([fixture.second])
    handler.receiving(false)
    XCTAssertEqual(store.boxes.count, 2)
    XCTAssertEqual(store.boxes.first(where: { $0.id == destination })?.items.count, 2)
    XCTAssertFalse(store.showRenameBox)
    XCTAssertFalse(shelf.receiving)
    XCTAssertFalse(shelf.failed)
    XCTAssertEqual(try String(contentsOf: fixture.first), "original one")
  }

  @MainActor func testCapturedDestinationSurvivesSelectionChangesWithoutOpeningWindows() throws {
    let application = NSApplication.shared
    let before = application.windows.count
    let store = ParcelStore(persist: false)
    let first = try XCTUnwrap(store.selectedBox)
    let shelf = DropPopupController(store: store)
    let handler = try XCTUnwrap(shelf.beginDrop(into: first))
    _ = store.shelfDestination(nil)
    let fixture = try makeFiles()
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    handler.receive([fixture.first])
    XCTAssertEqual(store.boxes.first(where: { $0.id == first })?.items.count, 1)
    XCTAssertEqual(store.current?.items.count, 0)
    XCTAssertEqual(application.windows.count, before)
  }

  @MainActor func testBusyDestinationRejectsDropAndFailuresRemainVisible() throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    store.phase = .packing
    XCTAssertNil(shelf.beginDrop(into: nil))
    XCTAssertEqual(store.boxes.count, 1)
    store.phase = .open
    let handler = try XCTUnwrap(shelf.beginDrop(into: store.selectedBox))
    handler.receive([URL(fileURLWithPath: "/missing-parcel-shelf-fixture")])
    XCTAssertTrue(shelf.failed)
    XCTAssertTrue(shelf.expanded)
    XCTAssertFalse(shelf.message.isEmpty)
    XCTAssertEqual(store.current?.items.count, 0)
  }

  @MainActor func testDuplicateDropDoesNotDuplicateReferences() throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    let fixture = try makeFiles()
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    let handler = try XCTUnwrap(shelf.beginDrop(into: store.selectedBox))
    handler.receive([fixture.first, fixture.first])
    handler.receive([fixture.first])
    XCTAssertEqual(store.current?.items.count, 1)
    XCTAssertFalse(shelf.failed)
  }

  @MainActor func testPartialPromiseFailureIsNotOverwrittenByLaterSuccess() throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    let fixture = try makeFiles()
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    let handler = try XCTUnwrap(shelf.beginDrop(into: nil))
    handler.receiving(true)
    handler.failure("One promised file could not be received.")
    handler.receive([fixture.first])
    handler.receiving(false)
    XCTAssertTrue(shelf.failed)
    XCTAssertTrue(shelf.message.contains("One promised file"))
    XCTAssertEqual(store.current?.items.count, 1)
    XCTAssertNil(store.error)
  }

  @MainActor func testBrowserImageAndPromiseTypesAreRecognizedWithoutReadingContents() throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    guard board.setString("Parcel test", forType: .string) else {
      throw XCTSkip("The execution sandbox cannot connect to the macOS pasteboard service.")
    }
    let promiseType = try XCTUnwrap(NSFilePromiseReceiver.readableDraggedTypes.first)
    for type in [NSPasteboard.PasteboardType.png, .tiff, .fileURL, .init(promiseType)] {
      board.declareTypes([type], owner: nil)
      XCTAssertTrue(FileDropSurface.supports(board), type.rawValue)
    }
    board.declareTypes([.string], owner: nil)
    XCTAssertFalse(FileDropSurface.supports(board))
  }

  @MainActor func testPackingFailureStaysInShelfWithoutHubAlert() throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    _ = try XCTUnwrap(shelf.beginDrop(into: store.selectedBox))
    store.boxes[0].items = [ParcelItem(
      sourcePath: "/missing-parcel-pack-fixture", displayName: "Missing file.txt")]
    shelf.pack()
    XCTAssertTrue(shelf.failed)
    XCTAssertTrue(shelf.message.contains("missing"))
    XCTAssertNil(store.error)
    XCTAssertEqual(store.phase, .open)
  }

  @MainActor func testRemovedDestinationCannotSilentlyReceiveIntoAnotherParcel() {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    let original = store.boxes
    XCTAssertNil(shelf.beginDrop(into: UUID()))
    XCTAssertEqual(store.boxes, original)
    XCTAssertEqual(store.selectedBox, original[0].id)
  }

  private func makeFiles() throws -> (folder: URL, first: URL, second: URL) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let first = folder.appendingPathComponent("one.txt")
    let second = folder.appendingPathComponent("two.txt")
    try "original one".write(to: first, atomically: true, encoding: .utf8)
    try "original two".write(to: second, atomically: true, encoding: .utf8)
    return (folder, first, second)
  }
}

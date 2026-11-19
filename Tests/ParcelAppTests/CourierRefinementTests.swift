import AppKit
import ParcelCore
import UniformTypeIdentifiers
import XCTest
@testable import ParcelApp

final class CourierRefinementTests: XCTestCase {
  func testOutboundDragPublishesModernAndLegacyFileRepresentations() {
    let url = URL(fileURLWithPath: "/tmp/Parcel drag test.txt")
    let writer = NativeFileDragWriter(url)
    let types = writer.writableTypes(for: .withUniqueName())
    XCTAssertTrue(types.contains(.fileURL))
    XCTAssertTrue(types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")))
    XCTAssertEqual(writer.pasteboardPropertyList(forType: .fileURL) as? String, url.absoluteString)
    XCTAssertEqual(writer.pasteboardPropertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? NSArray, [url.path] as NSArray)
  }
  func testOutboundTextDragPublishesPlainTextInsteadOfAFile() {
    let writer = NativeTextDragWriter("Selected words")
    XCTAssertEqual(writer.writableTypes(for: .withUniqueName()), [.string])
    XCTAssertEqual(writer.pasteboardPropertyList(forType: .string) as? String, "Selected words")
  }

  @MainActor func testPastedTextStaysPackageableButDragsAsInlineText() throws {
    let store = ParcelStore(persist: false)
    store.ingestText("Selected words")
    let item = try XCTUnwrap(store.items.last)
    XCTAssertEqual(item.inlineText, "Selected words")
    XCTAssertTrue(FileManager.default.fileExists(atPath: item.sourcePath))
  }
  @MainActor func testSelectedItemsCollapseIntoOneReversibleStackIcon() throws {
    let store = ParcelStore(persist: false)
    store.boxes[0].items = [
      ParcelItem(sourcePath: "/tmp/stack-one.txt", displayName: "One.txt"),
      ParcelItem(sourcePath: "/tmp/stack-two.txt", displayName: "Two.txt"),
      ParcelItem(sourcePath: "/tmp/separate.txt", displayName: "Separate.txt"),
    ]
    store.selectedItems = Set(store.boxes[0].items.prefix(2).map(\.id))
    store.stackSelected()
    let compact = store.compactItems(store.items)
    XCTAssertEqual(compact.count, 2)
    let representative = try XCTUnwrap(compact.first { $0.stackID != nil })
    XCTAssertEqual(store.stackCount(of: representative, in: store.boxes[0]), 2)
    store.unstack(representative.id)
    XCTAssertEqual(store.compactItems(store.items).count, 3)
    XCTAssertTrue(store.items.allSatisfy { $0.stackID == nil })
  }
  @MainActor func testKeyboardSummonOpensDashboardAndTabMovesWidgetPages() async throws {
    let store = ParcelStore(persist: false)
    let boxID = try XCTUnwrap(store.selectedBox)
    store.boxes[0].items = [
      ParcelItem(sourcePath: "/tmp/keyboard-one.txt", displayName: "One"),
      ParcelItem(sourcePath: "/tmp/keyboard-two.txt", displayName: "Two"),
    ]
    let shelf = DropPopupController(store: store)
    shelf.summon()
    XCTAssertTrue(shelf.toolsVisible)
    XCTAssertEqual(shelf.activeModule, .dashboard)
    XCTAssertEqual(shelf.focusedBox, boxID)
    let binding = CourierShortcutStore.shared.binding(for: .nextFile)
    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
      modifierFlags: NSEvent.ModifierFlags(rawValue: binding.modifiers), timestamp: 0, windowNumber: 0,
      context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false,
      keyCode: binding.keyCode))
    XCTAssertTrue(shelf.handleCourierKey(event))
    XCTAssertNil(shelf.keyboardFocusedItem)
    shelf.dismiss()
  }

  @MainActor func testEmptyHoverOpensEveryStyleWithoutShowingNewOrRecentChoices() async throws {
    let name = "CourierDirectHover-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ParcelStore(persist: false)
    let pinned = try XCTUnwrap(store.selectedBox)
    store.toggleParcelPin(pinned)
    _ = store.shelfDestination(nil)
    for style in CourierViewStyle.allCases {
      for side in CourierSide.allCases {
        let shelf = DropPopupController(store: store, defaults: defaults, folderHoverDelay: 0.02)
        shelf.side = side; shelf.viewStyle = style
        shelf.courierHoverChanged(true)
        try await Task.sleep(for: .milliseconds(45))
        XCTAssertTrue(shelf.showingFolder, "\(side) \(style)")
        XCTAssertEqual(shelf.focusedBox, pinned)
        XCTAssertTrue(shelf.destinations.isEmpty)
        XCTAssertEqual(shelf.arrangement.side, side)
        shelf.dismiss()
      }
    }
  }

  @MainActor func testQuickLookReplacesHoveredFileAndClosesHalfASecondAfterLeaving() async throws {
    let preview = CourierHoverPreview(enterDelay: .milliseconds(10))
    let first = ParcelItem(sourcePath: "/first.txt", displayName: "First")
    let second = ParcelItem(sourcePath: "/second.txt", displayName: "Second")
    preview.hover(first, inside: true)
    try await Task.sleep(for: .milliseconds(40))
    XCTAssertEqual(preview.item?.id, first.id)
    preview.hover(second, inside: true)
    preview.hover(first, inside: false)
    try await Task.sleep(for: .milliseconds(40))
    XCTAssertEqual(preview.item?.id, second.id)
    preview.hover(second, inside: false)
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(preview.item?.id, second.id)
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertNil(preview.item)
    preview.hover(first, inside: true)
    preview.clear()
    try await Task.sleep(for: .milliseconds(40))
    XCTAssertNil(preview.item)
  }

  @MainActor func testPreviewHandoffCancelsExpiryUntilPointerLeavesPreview() async throws {
    let preview = CourierHoverPreview(enterDelay: .milliseconds(5), exitDelay: .milliseconds(90))
    let item = ParcelItem(sourcePath: "/handoff.csv", displayName: "Handoff.csv")
    preview.hover(item, inside: true)
    try await Task.sleep(for: .milliseconds(25))
    preview.hover(item, inside: false)
    preview.previewHover(true)
    try await Task.sleep(for: .milliseconds(140))
    XCTAssertEqual(preview.item?.id, item.id)
    XCTAssertTrue(preview.isInsidePreview)
    preview.previewHover(false)
    try await Task.sleep(for: .milliseconds(35))
    XCTAssertNotNil(preview.item)
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertNil(preview.item)
    preview.clear()
    XCTAssertFalse(preview.isInsidePreview)
  }

  @MainActor func testSidePreviewIsInteractiveNativeQuickLookWithTwoAxisScrollingAndReleasesOnHide() async throws {
    _ = NSApplication.shared
    let parent = ShelfPanel(contentRect: CGRect(x: 30, y: 50, width: 340, height: 400),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    parent.isReleasedWhenClosed = false
    let controller = CourierSidePreviewController()
    defer { controller.hide(); parent.close() }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
    try "Name,Count\nPreview,3\n".write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    let item = ParcelItem(sourcePath: file.path, displayName: "Preview.csv")
    let frame = CGRect(x: 382, y: 80, width: 360, height: 320)
    controller.show(item, frame: frame, scale: 1, parent: parent, hover: { _ in }, activity: {}, close: {})
    let panel = try XCTUnwrap(controller.panel)
    XCTAssertTrue(panel.parent === parent)
    XCTAssertEqual(panel.frame, frame)
    XCTAssertFalse(panel.ignoresMouseEvents)
    XCTAssertFalse(panel.canBecomeMain)
    let scroll = ScrollableFilePreview.PreviewScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 240))
    parent.contentView?.addSubview(scroll)
    scroll.load(item.effectiveURL)
    scroll.layoutSubtreeIfNeeded()
    defer { scroll.preview.close() }
    XCTAssertTrue(scroll.hasVerticalScroller)
    XCTAssertTrue(scroll.hasHorizontalScroller)
    XCTAssertFalse(scroll.autohidesScrollers)
    XCTAssertTrue(scroll.documentView === scroll.preview)
    XCTAssertGreaterThan(scroll.preview.frame.width, scroll.contentSize.width)
    XCTAssertGreaterThan(scroll.preview.frame.height, scroll.contentSize.height)
    XCTAssertEqual((scroll.preview.previewItem as? NSURL)?.path, item.effectiveURL.path)
    scroll.contentView.scroll(to: CGPoint(x: 100, y: 100))
    XCTAssertEqual(scroll.contentView.bounds.minX, 100, accuracy: 1)
    XCTAssertEqual(scroll.contentView.bounds.minY, 100, accuracy: 1)
    try await Task.sleep(for: .milliseconds(300))
    controller.hide()
    XCTAssertFalse(panel.isVisible)
    XCTAssertNil(panel.parent)
    XCTAssertNil(panel.contentView)
    try await Task.sleep(for: .milliseconds(50))
    controller.show(item, frame: frame, scale: 0.75, parent: parent, hover: { _ in }, activity: {}, close: {})
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertTrue(controller.panel === panel)
    XCTAssertNotNil(panel.contentView)
    controller.hide()
    try await Task.sleep(for: .milliseconds(50))
  }

  @MainActor func testClipboardSearchAndParcelPickerPanelsAcceptImmediateInteraction() throws {
    _ = NSApplication.shared
    let parent = ShelfPanel(contentRect: CGRect(x: 300, y: 300, width: 360, height: 240),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    parent.isReleasedWhenClosed = false
    parent.orderFront(nil)
    defer { parent.close() }

    let clipboard = CourierClipboardController()
    clipboard.show(parent: parent, skin: .night, hover: { _ in }, close: {}, addToParcel: { _ in },
      processImage: { _ in }, keyHandler: { _ in false })
    let clipboardPanel = try XCTUnwrap(clipboard.panel)
    XCTAssertTrue(clipboardPanel.styleMask.contains(.nonactivatingPanel))
    XCTAssertTrue(clipboardPanel.canBecomeKey)
    clipboard.hide()

    let store = ParcelStore(persist: false)
    let search = CourierSearchPanelController()
    search.show(store: store, boxID: try XCTUnwrap(store.selectedBox), parent: parent, skin: .night,
      inside: { _ in }, close: {}, open: { _ in }, menu: { _ in NSMenu() }, keyHandler: { _ in false })
    let searchPanel = try XCTUnwrap(search.panel)
    XCTAssertFalse(searchPanel.styleMask.contains(.nonactivatingPanel))
    XCTAssertTrue(searchPanel.canBecomeKey)
    search.hide()

    store.boxes.append(ParcelBox(name: "Second parcel"))
    let picker = CourierParcelPickerController()
    picker.show(boxes: store.boxes, current: store.selectedBox, parent: parent, skin: .night,
      hover: { _ in }, select: { store.selectBox($0) }, beginDrop: { _ in nil })
    let pickerPanel = try XCTUnwrap(picker.panel)
    XCTAssertFalse(pickerPanel.styleMask.contains(.nonactivatingPanel))
    XCTAssertTrue(pickerPanel.canBecomeKey)
    picker.hide()
  }


  @MainActor func testOnlyParkedDialUsesShortStraightMenuLayout() throws {
    _ = NSApplication.shared
    let name = "MenuDial-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ParcelStore(persist: false)
    let identifier = try XCTUnwrap(store.selectedBox)
    store.boxes[0].items = (0..<8).map { ParcelItem(sourcePath: "/tmp/file-\($0).txt", displayName: "File \($0)") }
    let shelf = DropPopupController(store: store, defaults: defaults)
    shelf.viewStyle = .dial; shelf.side = .right
    shelf.select(identifier)
    let desktop = shelf.arrangement
    XCTAssertEqual(desktop.side, .right)
    shelf.parkInMenuBar()
    let screen = try XCTUnwrap(NSScreen.main).visibleFrame
    shelf.menuHover(true, anchor: CGRect(x: screen.maxX - 80, y: screen.maxY + 2, width: 30, height: 22))
    shelf.select(identifier)
    let menu = shelf.arrangement
    XCTAssertEqual(menu.side, .bottom)
    XCTAssertLessThan(try XCTUnwrap(menu.pane).height, try XCTUnwrap(desktop.pane).height)
    XCTAssertEqual(shelf.side, .right)
    shelf.returnFromMenuBar()
    shelf.dismiss()
  }

  @MainActor func testDialScrollCaptureIncludesEmptySpaceAndControlsButNotOtherWindows() {
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 600),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let other = NSWindow(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    other.isReleasedWhenClosed = false
    defer { window.close(); other.close() }
    let region = CourierScrollRegion.Region(frame: CGRect(x: 50, y: 50, width: 360, height: 500))
    window.contentView?.addSubview(region)
    var received: [CGFloat] = []
    region.scroll = { received.append($0) }
    for point in [CGPoint(x: 51, y: 51), CGPoint(x: 409, y: 549), CGPoint(x: 220, y: 300)] {
      XCTAssertTrue(region.consume(window: window, location: point, delta: -3, precise: true))
    }
    XCTAssertFalse(region.consume(window: other, location: CGPoint(x: 220, y: 300), delta: 1, precise: true))
    XCTAssertFalse(region.consume(window: window, location: CGPoint(x: 10, y: 10), delta: 1, precise: true))
    XCTAssertTrue(region.consume(window: window, location: CGPoint(x: 220, y: 300), delta: -1, precise: false))
    XCTAssertEqual(received, [-3, -3, -3, -12])
    region.isHidden = true
    XCTAssertFalse(region.consume(window: window, location: CGPoint(x: 220, y: 300), delta: 1, precise: true))
    region.stop()
  }

  @MainActor func testMenuBarClickTogglesNotchAndCannotInterruptPacking() async throws {
    let name = "CourierToggle-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store, defaults: defaults)
    shelf.restoreResident()
    XCTAssertTrue(shelf.isVisible)
    XCTAssertFalse(shelf.expanded)
    shelf.toggleMenuBar()
    XCTAssertTrue(shelf.parkedInMenuBar)
    XCTAssertTrue(shelf.isVisible)
    XCTAssertTrue(shelf.toolsVisible)
    XCTAssertEqual(shelf.activeModule, .dashboard)
    shelf.toggleMenuBar()
    XCTAssertTrue(shelf.parkedInMenuBar)
    try await Task.sleep(for: .milliseconds(180))
    XCTAssertTrue(shelf.isVisible)
    XCTAssertFalse(shelf.expanded)
    shelf.toggleMenuBar()
    XCTAssertTrue(shelf.isVisible)
    store.phase = .packing
    shelf.toggleMenuBar()
    XCTAssertTrue(shelf.isVisible)
    store.phase = .open
    shelf.toggleMenuBar()
    try await Task.sleep(for: .milliseconds(180))
    XCTAssertTrue(shelf.isVisible)
    XCTAssertFalse(shelf.expanded)
  }

  @MainActor func testMissingFileIconsStillUseRegisteredDocumentTypesRatherThanGenericArtwork() throws {
    for extensionName in ["xlsx", "csv", "pdf", "numbers", "png", "mov"] {
      let type = try XCTUnwrap(UTType(filenameExtension: extensionName))
      let url = URL(fileURLWithPath: "/missing-review/Example." + extensionName)
      let icon = FileTypeIcon.image(for: url)
      let expected: NSImage
      if !type.conforms(to: .image), !type.conforms(to: .movie), !type.conforms(to: .audio),
        let application = NSWorkspace.shared.urlForApplication(toOpen: url) {
        expected = NSWorkspace.shared.icon(forFile: application.path)
      } else { expected = NSWorkspace.shared.icon(for: type) }
      XCTAssertEqual(icon.tiffRepresentation, expected.tiffRepresentation)
    }
  }

  @MainActor func testCourierDoubleClickUsesDedicatedActionAndNeverStartsAFileDrag() throws {
    let surface = DragOutSurface.SendingView()
    var singles = 0
    var doubles = 0
    surface.tap = { singles += 1 }
    surface.doubleTap = { doubles += 1 }
    for count in [1, 2] {
      let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
        modifierFlags: [], timestamp: Double(count), windowNumber: 0, context: nil,
        eventNumber: count, clickCount: count, pressure: 1))
      surface.mouseDown(with: event)
      surface.mouseUp(with: event)
    }
    XCTAssertEqual(singles, 1)
    XCTAssertEqual(doubles, 1)
  }

  @MainActor func testCourierPickupUsesDefaultsWithoutSavingAnExtraDesktopCopy() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
    try "ZIP drag fixture".write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    let store = ParcelStore(persist: false)
    store.ingest([file])
    store.packaging.format = .zip
    store.packaging.strength = .heavy
    store.packaging.saveToDesktop = true
    let original = store.packaging
    let shelf = DropPopupController(store: store)
    var callbacks = 0
    let archive: URL? = await withCheckedContinuation { continuation in
      shelf.preparePrimaryArchive { url in callbacks += 1; continuation.resume(returning: url) }
    }
    let result = try XCTUnwrap(archive)
    defer { StoragePaths.deleteOwned(result.deletingLastPathComponent()) }
    XCTAssertEqual(callbacks, 1)
    XCTAssertEqual(result.pathExtension, "zip")
    XCTAssertTrue(FileTree.isInside(result, directory: StoragePaths.exports))
    XCTAssertEqual(Array(try Data(contentsOf: result).prefix(2)), [0x50, 0x4b])
    XCTAssertEqual(store.packaging, original)
    XCTAssertEqual(try String(contentsOf: file), "ZIP drag fixture")
    var reuse: URL?
    shelf.preparePrimaryArchive { reuse = $0 }
    XCTAssertEqual(reuse, result)
  }

  @MainActor func testRightDragPreparesOnceAndReleaseBeforeReadyDoesNotSendAnything() throws {
    var menuInvoked = false
    let menuItem = CourierMenuAction("Test action") { menuInvoked = true }
    XCTAssertTrue(NSApplication.shared.sendAction(try XCTUnwrap(menuItem.action), to: menuItem.target, from: menuItem))
    XCTAssertTrue(menuInvoked)
    let view = DragOutSurface.SendingView()
    let down = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
      modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    let drag = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDragged, location: CGPoint(x: 30, y: 20),
      modifierFlags: [], timestamp: 2, windowNumber: 0, context: nil, eventNumber: 2, clickCount: 1, pressure: 1))
    var calls = 0
    var callback: ((URL?) -> Void)?
    view.archiveForDrag = { ready in calls += 1; callback = ready }
    view.rightMouseDown(with: down)
    view.rightMouseDragged(with: drag)
    view.rightMouseDragged(with: drag)
    XCTAssertEqual(calls, 1)
    view.rightMouseUp(with: drag)
    callback?(URL(fileURLWithPath: "/not-sent.zip"))
    XCTAssertNotNil(callback)
  }

  @MainActor func testLeftDragOnParcelNameRequestsOnePackedArchive() throws {
    let view = DragOutSurface.SendingView()
    let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
      modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    let drag = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDragged, location: CGPoint(x: 30, y: 20),
      modifierFlags: [], timestamp: 2, windowNumber: 0, context: nil, eventNumber: 2, clickCount: 1, pressure: 1))
    var calls = 0
    view.archiveForDrag = { _ in calls += 1 }
    view.mouseDown(with: down)
    view.mouseDragged(with: drag)
    view.mouseDragged(with: drag)
    XCTAssertEqual(calls, 1)
    view.mouseUp(with: drag)
  }

  @MainActor func testOutgoingDragArtworkIsCenteredUnderPointer() {
    let frame = DragOutSurface.SendingView.centeredDragFrame(
      at: CGPoint(x: 120, y: 80), size: CGSize(width: 92, height: 48))
    XCTAssertEqual(frame.midX, 120, accuracy: 0.001)
    XCTAssertEqual(frame.midY, 80, accuracy: 0.001)
  }

  @MainActor func testTrashDropRemovesOnlyTheHoveredParcelItemAndKeepsOriginal() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("First.txt")
    let second = root.appendingPathComponent("Second.txt")
    try "one".write(to: first, atomically: true, encoding: .utf8)
    try "two".write(to: second, atomically: true, encoding: .utf8)
    let store = ParcelStore(persist: false)
    store.ingest([first, second])
    let boxID = try XCTUnwrap(store.selectedBox)
    let item = try XCTUnwrap(store.boxes.first?.items.first(where: { $0.effectiveURL == first }))
    let shelf = DropPopupController(store: store)
    let handler = try XCTUnwrap(shelf.beginItemDeleteDrop(item.id, from: boxID))
    handler.receive([second])
    XCTAssertEqual(store.boxes.first?.items.count, 2)
    handler.receive([first])
    XCTAssertEqual(store.boxes.first?.items.map(\.effectiveURL), [second])
    XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
  }

  @MainActor func testTrashDropRemovesEveryMemberOfDraggedStack() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("First.txt")
    let second = root.appendingPathComponent("Second.txt")
    let third = root.appendingPathComponent("Third.txt")
    try "one".write(to: first, atomically: true, encoding: .utf8)
    try "two".write(to: second, atomically: true, encoding: .utf8)
    try "three".write(to: third, atomically: true, encoding: .utf8)
    let store = ParcelStore(persist: false)
    store.ingest([first, second, third])
    let boxID = try XCTUnwrap(store.selectedBox)
    let firstItem = try XCTUnwrap(store.boxes.first?.items.first(where: { $0.effectiveURL == first }))
    let secondItem = try XCTUnwrap(store.boxes.first?.items.first(where: { $0.effectiveURL == second }))
    store.selectedItems = [firstItem.id, secondItem.id]
    store.stackSelected()
    let shelf = DropPopupController(store: store)
    let handler = try XCTUnwrap(shelf.beginItemDeleteDrop(firstItem.id, from: boxID))
    handler.receive([first])
    XCTAssertEqual(store.boxes.first?.items.count, 3)
    handler.receive([first, second])
    XCTAssertEqual(store.boxes.first?.items.map(\.effectiveURL), [third])
    XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
  }

  @MainActor func testFinderServiceReadsFileURLsAndLegacyFilenamesWithoutAcceptingWebLinks() throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    board.writeObjects([URL(fileURLWithPath: "/tmp/Service fixture.txt") as NSURL])
    XCTAssertEqual(ParcelFileService.fileURLs(from: board).map(\.path), ["/tmp/Service fixture.txt"])
    board.clearContents()
    board.setPropertyList(["/tmp/Another.txt"], forType: .init("NSFilenamesPboardType"))
    XCTAssertEqual(ParcelFileService.fileURLs(from: board).map(\.path), ["/tmp/Another.txt"])
    board.clearContents()
    board.writeObjects([URL(string: "https://example.com/private")! as NSURL])
    XCTAssertTrue(ParcelFileService.fileURLs(from: board).isEmpty)
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Config/Info.plist"))
    let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    let services = try XCTUnwrap(plist["NSServices"] as? [[String: Any]])
    XCTAssertEqual(services.first?["NSMessage"] as? String, "sendToParcels")
  }

  @MainActor func testClipboardNaturalSearchAndTypeFiltersCompose() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let text = ClipboardEntry(kind: .text, createdAt: now, text: "Quarterly revenue notes",
      title: "Quarterly revenue notes", detail: "23 characters")
    let image = ClipboardEntry(kind: .image, createdAt: now, paths: ["/tmp/chart.png"],
      title: "Copied image", detail: "1200 × 800")
    XCTAssertTrue(ClipboardHistoryStore.matches(text, search: "text revenue today", filter: nil, now: now))
    XCTAssertFalse(ClipboardHistoryStore.matches(image, search: "text revenue today", filter: nil, now: now))
    XCTAssertTrue(ClipboardHistoryStore.matches(image, search: "images today", filter: .image, now: now))
    XCTAssertFalse(ClipboardHistoryStore.matches(image, search: "images today", filter: .text, now: now))
    let history = ClipboardHistoryStore(persist: false)
    history.cycleFilter(); XCTAssertEqual(history.filter, .text)
    history.cycleFilter(); XCTAssertEqual(history.filter, .image)
    history.cycleFilter(); XCTAssertEqual(history.filter, .file)
    history.cycleFilter(); XCTAssertNil(history.filter)
  }

  func testClipboardLinksAreParsedAndShorteningRequestKeepsTheWholeURL() throws {
    let long = try XCTUnwrap(URL(string: "https://example.com/report?q=parcel&month=november#totals"))
    let entry = ClipboardEntry(kind: .text,
      text: "Use \(long.absoluteString), then ignore mailto:support@example.com and \(long.absoluteString)",
      title: "Links", detail: "Parsed text")
    XCTAssertEqual(entry.linkURLs, [long])
    XCTAssertTrue(ClipboardEntry(kind: .text, text: "https://da.gd/alreadyShort",
      title: "Short", detail: "Link").linkURLs.isEmpty)
    let request = try LinkShortener.request(for: long)
    XCTAssertEqual(request.url?.host, "da.gd")
    XCTAssertEqual(request.url?.path, "/s")
    XCTAssertEqual(request.httpMethod, "GET")
    let query = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }).queryItems
    XCTAssertEqual(query?.first(where: { $0.name == "url" })?.value, long.absoluteString)
  }

  @MainActor func testShortenedLinkIsCopiedAndImmediatelyAddedToHistory() async throws {
    let original = try XCTUnwrap(URL(string: "https://example.com/a/very/long/link"))
    let shortened = try XCTUnwrap(URL(string: "https://da.gd/parcelTest"))
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let history = ClipboardHistoryStore(persist: false)
    await history.shortenAndCopy(original, using: { _ in shortened }, pasteboard: board)
    XCTAssertEqual(board.string(forType: .string), shortened.absoluteString)
    XCTAssertEqual(history.entries.first?.text, shortened.absoluteString)
    XCTAssertEqual(history.entries.first?.detail, "Shortened link · da.gd")
  }

  @MainActor func testParcelImageNativeMenuOffersProcessingAndOCR() {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    let image = ParcelItem(sourcePath: "/tmp/menu-image.png", displayName: "menu-image.png")
    let titles = shelf.fileContextMenu(for: image).items.map(\.title)
    XCTAssertTrue(titles.contains("Process image…"))
    XCTAssertTrue(titles.contains("Copy text with OCR"))
  }

  @MainActor func testClipboardShortcutTogglesBetweenArrowAndDashboard() throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    shelf.summon()
    shelf.showChoices()
    let binding = CourierShortcutStore.shared.binding(for: .clipboard)
    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
      modifierFlags: NSEvent.ModifierFlags(rawValue: binding.modifiers), timestamp: 0, windowNumber: 0,
      context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false,
      keyCode: binding.keyCode))
    XCTAssertTrue(shelf.handleCourierKey(event))
    XCTAssertEqual(shelf.activeModule, .clipboard)
    XCTAssertTrue(shelf.handleCourierKey(event))
    XCTAssertEqual(shelf.activeModule, .dashboard)
    shelf.dismiss()
  }

  @MainActor func testClickedClipboardStaysOpenUntilExplicitlyClosed() async throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    shelf.summon()
    shelf.showChoices()
    shelf.toggleClipboard()
    shelf.clipboardHoverChanged(false)
    try await Task.sleep(for: .milliseconds(1700))
    XCTAssertTrue(shelf.isClipboardVisible)
    shelf.toggleClipboard()
    XCTAssertFalse(shelf.isClipboardVisible)
    shelf.dismiss()
  }

  @MainActor func testHoverClipboardAllowsHandoffThenClosesWhenPointerLeavesBothPanels() async throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    shelf.summon()
    shelf.clipboardHoverChanged(true)
    shelf.clipboardHoverChanged(false)
    try await Task.sleep(for: .milliseconds(500))
    shelf.clipboardHoverChanged(true)
    try await Task.sleep(for: .milliseconds(700))
    XCTAssertTrue(shelf.isClipboardVisible)
    shelf.clipboardHoverChanged(false)
    try await Task.sleep(for: .milliseconds(1100))
    XCTAssertFalse(shelf.isClipboardVisible)
    shelf.dismiss()
  }

  @MainActor func testHoverAndClickLifecycleMatchesForSearchAndOptions() async throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    shelf.summon()

    shelf.searchHoverChanged(true)
    XCTAssertTrue(shelf.isSearchVisible)
    shelf.searchHoverChanged(false)
    try await Task.sleep(for: .milliseconds(1100))
    XCTAssertFalse(shelf.isSearchVisible)
    shelf.toggleSearch()
    shelf.searchHoverChanged(false)
    try await Task.sleep(for: .milliseconds(1100))
    XCTAssertTrue(shelf.isSearchVisible)
    shelf.toggleSearch()

    shelf.optionsHoverChanged(true, delete: {})
    XCTAssertTrue(shelf.isOptionsVisible)
    shelf.optionsHoverChanged(false, delete: {})
    try await Task.sleep(for: .milliseconds(1100))
    XCTAssertFalse(shelf.isOptionsVisible)
    shelf.toggleOptions(delete: {})
    shelf.optionsHoverChanged(false, delete: {})
    try await Task.sleep(for: .milliseconds(1100))
    XCTAssertTrue(shelf.isOptionsVisible)
    shelf.toggleOptions(delete: {})
    shelf.dismiss()
  }

  @MainActor func testSelectingAnotherParcelKeepsItsFilesOpen() async throws {
    let store = ParcelStore(persist: false)
    var second = ParcelBox(name: "Second parcel")
    second.items = [ParcelItem(sourcePath: "/tmp/second.txt", displayName: "second.txt")]
    store.boxes.append(second)
    let shelf = DropPopupController(store: store)
    shelf.summon()
    shelf.select(second.id)
    try await Task.sleep(for: .milliseconds(4200))
    XCTAssertTrue(shelf.isVisible)
    XCTAssertTrue(shelf.showingFolder)
    XCTAssertEqual(shelf.focusedBox, second.id)
    shelf.dismiss()
  }

  @MainActor func testHoverClipboardClosesOnConfiguredIdleTimeout() async throws {
    let name = "ParcelClipboardIdle-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(5, forKey: "parcel.idleTimeout")
    let shelf = DropPopupController(store: ParcelStore(persist: false), defaults: defaults)
    shelf.summon()
    shelf.clipboardHoverChanged(true)
    shelf.clipboardHoverChanged(false)
    try await Task.sleep(for: .milliseconds(5400))
    XCTAssertFalse(shelf.isVisible)
    XCTAssertFalse(shelf.isClipboardVisible)
  }

  @MainActor func testSummonedShelfDoesNotImmediatelyCloseBeforePointerEnters() async throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    shelf.summonFromMouseShake()
    shelf.hoverChanged(false)
    try await Task.sleep(for: .milliseconds(500))
    XCTAssertTrue(shelf.isVisible)
    XCTAssertTrue(shelf.expanded)
    shelf.dismiss()
  }

  @MainActor func testClickPinsAnAlreadyHoverOpenedClipboard() async throws {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    shelf.summon()
    shelf.clipboardHoverChanged(true)
    shelf.toggleClipboard()
    shelf.clipboardHoverChanged(false)
    try await Task.sleep(for: .milliseconds(1700))
    XCTAssertTrue(shelf.isClipboardVisible)
    shelf.toggleClipboard()
    XCTAssertFalse(shelf.isClipboardVisible)
    shelf.dismiss()
  }

  @MainActor func testDeletingMissingSourceClearsStaleOriginalUnavailableError() throws {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
    let store = ParcelStore(persist: false)
    var box = ParcelBox(name: "PDF")
    box.items = [ParcelItem(sourcePath: missing.path, displayName: missing.lastPathComponent)]
    store.boxes = [box]
    store.selectedBox = store.boxes[0].id
    store.error = "Original file is unavailable."
    store.remove([store.boxes[0].items[0].id])
    XCTAssertNil(store.error)
    XCTAssertTrue(store.boxes[0].items.isEmpty)
  }
}

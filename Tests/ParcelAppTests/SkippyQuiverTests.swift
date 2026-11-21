import ParcelCore
import AppKit
import XCTest
@testable import ParcelApp

final class SkippyQuiverTests: XCTestCase {
  @MainActor func testHistoryRespectsConcealedContentAndPause() {
    let history = ClipboardHistoryStore(persist: false)
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    board.setString("private sample", forType: .string)
    board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
    history.capture(board)
    XCTAssertTrue(history.entries.isEmpty)
    board.clearContents()
    board.setString("ordinary sample", forType: .string)
    history.captureEnabled = false
    history.capture(board)
    XCTAssertTrue(history.entries.isEmpty)
    history.captureEnabled = true
    history.capture(board)
    XCTAssertEqual(history.entries.first?.text, "ordinary sample")
  }

  func testSnapTargetsUseTheChosenDisplaysCoordinates() {
    let screen = CGRect(x: -1440, y: 200, width: 1440, height: 900)
    let visible = screen.insetBy(dx: 0, dy: 28)
    let cases: [(CGPoint, QuiverSurface)] = [
      (.init(x: -720, y: 1098), .notch), (.init(x: -20, y: 1098), .menu),
      (.init(x: -1040, y: 1098), .top), (.init(x: -720, y: 231), .bottom),
      (.init(x: -1433, y: 650), .left), (.init(x: -4, y: 650), .right),
      (.init(x: -720, y: 204), .dock), (.init(x: -500, y: 600), .floating)]
    for (point, expected) in cases {
      XCTAssertEqual(QuiverSurface.snapped(at: point, screen: screen, visible: visible), expected)
      let anchor = CGRect(origin: point, size: CGSize(width: 30, height: 24))
      let frame = QuiverSurface.panel(at: anchor, within: visible, size: CGSize(width: 460, height: 340))
      XCTAssertTrue(visible.contains(frame))
    }
  }

  @MainActor func testFloatingMarkUnfoldsPinsAndOpensSelectedToolAtTheButton() async throws {
    let suite = "SkippyQuiverTests-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("Floating", forKey: "skippy.surface")
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store, defaults: defaults)
    let widgets = NotchWidgetStore(defaults: defaults)
    let tools = NotchToolStore(defaults: defaults)
    let quiver = SkippyQuiver(defaults: defaults, shelf: shelf, widgets: widgets, tools: tools)
    quiver.install()
    defer { shelf.dismiss(); quiver.strip.window?.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(100))
    let mark = try XCTUnwrap(quiver.anchor)
    quiver.hover(true)
    XCTAssertTrue(quiver.unfolded)
    let markView = try XCTUnwrap(quiver.strip.subviews.last as? QuiverMark)
    var widths = Set<Int>()
    for _ in 0..<24 {
      try await Task.sleep(for: .milliseconds(13))
      XCTAssertTrue(quiver.strip.subviews.last === markView)
      XCTAssertEqual(try XCTUnwrap(quiver.anchor).midX, mark.midX, accuracy: 1)
      widths.insert(Int(quiver.strip.bounds.width))
    }
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      XCTAssertGreaterThan(widths.count, 2, "The native backplate must pass through intermediate widths")
    }
    XCTAssertEqual(try XCTUnwrap(quiver.anchor).midX, mark.midX, accuracy: 1)
    XCTAssertFalse(shelf.isVisible)
    let button = try XCTUnwrap(quiver.strip.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Notes" })
    button.performClick(nil)
    XCTAssertEqual(shelf.activeModule, .notes)
    XCTAssertTrue(shelf.isVisible)
    try await Task.sleep(for: .milliseconds(240))
    let panel = try XCTUnwrap(shelf.presentationFrame)
    let screen = try XCTUnwrap(button.window?.screen)
    XCTAssertTrue(screen.visibleFrame.contains(panel))
    let anchor = try XCTUnwrap(button.window).convertToScreen(button.convert(button.bounds, to: nil))
    let expected = QuiverSurface.panel(at: quiver.toolAnchor(anchor), within: screen.visibleFrame, size: panel.size)
    // WindowServer aligns window origins to physical pixels.
    let pixel = 1 / screen.backingScaleFactor
    XCTAssertEqual(panel.minX, expected.minX, accuracy: pixel)
    XCTAssertEqual(panel.minY, expected.minY, accuracy: pixel)
    shelf.dismiss()
    XCTAssertFalse(shelf.isVisible)
    let window = quiver.strip.window
    let titles = quiver.strip.subviews.compactMap { ($0 as? NSButton)?.accessibilityLabel() }
    XCTAssertEqual(titles.count, 4)
    XCTAssertEqual(titles.last, "More arrows")
    quiver.openArrowFinder()
    XCTAssertTrue(quiver.strip.window === window)
    XCTAssertTrue(shelf.choosingArrow)
    shelf.dismiss()
    quiver.hover(false)
    try await Task.sleep(for: .seconds(2))
    XCTAssertFalse(quiver.unfolded)
    quiver.surface = .left
    XCTAssertEqual(defaults.string(forKey: "skippy.surface"), "Left edge")
    XCTAssertEqual(try XCTUnwrap(quiver.anchor).minX, screen.visibleFrame.minX, accuracy: 1)
    quiver.surface = .notch
    XCTAssertEqual(try XCTUnwrap(quiver.anchor).midX, screen.frame.midX, accuracy: 1)
    quiver.surface = .menu
    XCTAssertNotNil(quiver.strip.window)
    quiver.hover(true)
    XCTAssertNotNil(quiver.strip.subviews.first { $0.accessibilityLabel() == "File Shelf" })
  }
  @MainActor func testPreviewCanBeBrowsedThenCommittedWithoutReplacingAnOpenEditor() throws {
    let store = ParcelStore(persist: false)
    let popup = DropPopupController(store: store)
    let point = try XCTUnwrap(NSScreen.main).visibleFrame
    let anchor = CGRect(x: point.midX, y: point.maxY - 32, width: 31, height: 32)
    popup.quiverAnchor = { anchor }
    defer { popup.dismiss() }
    popup.previewArrow(.notes, at: anchor)
    XCTAssertTrue(popup.isArrowPreview)
    XCTAssertEqual(popup.activeModule, .notes)
    popup.previewArrow(.calculator, at: anchor)
    XCTAssertEqual(popup.activeModule, .calculator)
    popup.openArrow(.calculator, at: anchor)
    XCTAssertTrue(popup.isVisible)
    XCTAssertFalse(popup.isArrowPreview)
    popup.previewArrow(.notes, at: anchor)
    popup.dismissArrowPreview()
    XCTAssertTrue(popup.isVisible)
    XCTAssertEqual(popup.activeModule, .calculator)
    popup.dismiss()
    popup.previewArrow(.parcel, at: anchor)
    popup.dismissArrowPreview()
    XCTAssertFalse(popup.isVisible)
  }

  @MainActor func testShortcutResetClearsCollisionsIndependentOfKeyboardLayout() throws {
    let name = "Skippy.Shortcuts." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let keys = CourierShortcutStore(defaults: defaults)
    let k = CourierCommand.chooseArrow.defaultBinding
    XCTAssertFalse(keys.update(.tools, binding: .init(keyCode: k.keyCode, modifiers: k.modifiers, keyLabel: "alternate")))
    XCTAssertTrue(keys.update(.chooseArrow, binding: .init(keyCode: 47, modifiers: k.modifiers, keyLabel: ".")))
    XCTAssertTrue(keys.update(.tools, binding: k))
    keys.resetAll()
    let restored = CourierShortcutStore(defaults: defaults)
    for c in CourierCommand.allCases { XCTAssertEqual(restored.binding(for: c), c.defaultBinding) }
  }

}

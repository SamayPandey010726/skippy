import AppKit
import XCTest
@testable import ParcelApp

final class SkippyQuiverTests: XCTestCase {
  func testSnapTargetsUseTheChosenDisplaysCoordinates() {
    let screen = CGRect(x: -1440, y: 200, width: 1440, height: 900)
    let visible = screen.insetBy(dx: 0, dy: 28)
    let cases: [(CGPoint, QuiverSurface)] = [
      (.init(x: -720, y: 1098), .notch), (.init(x: -20, y: 1098), .menu),
      (.init(x: -1040, y: 1098), .top), (.init(x: -720, y: 231), .bottom),
      (.init(x: -1433, y: 650), .left), (.init(x: -4, y: 650), .right),
      (.init(x: -500, y: 600), .floating)]
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
    XCTAssertEqual(try XCTUnwrap(quiver.anchor).midX, mark.midX, accuracy: 1)
    XCTAssertFalse(shelf.isVisible)
    let button = try XCTUnwrap(quiver.strip.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == "Notes" })
    button.performClick(nil)
    XCTAssertEqual(shelf.activeModule, .notes)
    XCTAssertTrue(shelf.isVisible)
    let panel = try XCTUnwrap(shelf.presentationFrame)
    let screen = try XCTUnwrap(button.window?.screen)
    XCTAssertTrue(screen.visibleFrame.contains(panel))
    let anchor = try XCTUnwrap(button.window).convertToScreen(button.convert(button.bounds, to: nil))
    XCTAssertEqual(panel, QuiverSurface.panel(at: anchor, within: screen.visibleFrame, size: panel.size))
    shelf.dismiss()
    XCTAssertFalse(shelf.isVisible)
    quiver.hover(false)
    try await Task.sleep(for: .seconds(2))
    XCTAssertFalse(quiver.unfolded)
    quiver.surface = .left
    XCTAssertEqual(defaults.string(forKey: "skippy.surface"), "Left edge")
    XCTAssertEqual(try XCTUnwrap(quiver.anchor).minX, screen.visibleFrame.minX, accuracy: 1)
  }
}

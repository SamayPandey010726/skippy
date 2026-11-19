import AppKit
import Vision
import XCTest
@testable import ParcelApp

final class NotchToolsTests: XCTestCase {
  func testCalculatorPrecedenceAndInvalidInputs() {
    var expression = NotchCalculator("(24 + 8) / 2")
    XCTAssertEqual(expression.evaluate(), 16)
    var percentages = NotchCalculator("200 * 15%")
    XCTAssertEqual(percentages.evaluate(), 30)
    var divisionByZero = NotchCalculator("2 / 0")
    XCTAssertNil(divisionByZero.evaluate())
    var invalid = NotchCalculator("1 + system('open')")
    XCTAssertNil(invalid.evaluate())
    var incomplete = NotchCalculator("(1 + 2")
    XCTAssertNil(incomplete.evaluate())
  }
  func testDashboardIsDefaultAndParcelRemainsARealTool() {
    XCTAssertEqual(NotchModule.allCases.first, .dashboard)
    XCTAssertEqual(Set(NotchModule.allCases.map(\.rawValue)).count, NotchModule.allCases.count)
    XCTAssertTrue(NotchModule.allCases.contains(.parcel))
    XCTAssertTrue(NotchModule.allCases.contains(.clipboard))
    XCTAssertTrue(NotchModule.allCases.contains(.extract))
    XCTAssertTrue(NotchModule.allCases.contains(.qr))
    XCTAssertTrue(NotchModule.allCases.contains(.launcher))
  }

  @MainActor func testQuickNotePersistsLocally() throws {
    let suite = "NotchToolsTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = NotchToolStore(defaults: defaults)
    first.note = "Keep this near the notch"
    XCTAssertEqual(NotchToolStore(defaults: defaults).note, "Keep this near the notch")
  }

  @MainActor func testGeneratedQRCodeRoundTripsThroughVision() throws {
    let tools = NotchToolStore(defaults: .standard)
    let image = try XCTUnwrap(tools.generateQR("https://parcel.test/notch"))
    let data = try XCTUnwrap(image.tiffRepresentation)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
    let cgImage = try XCTUnwrap(bitmap.cgImage)
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    try VNImageRequestHandler(cgImage: cgImage).perform([request])
    XCTAssertEqual(request.results?.first?.payloadStringValue, "https://parcel.test/notch")
  }

  @MainActor func testParcelWidgetOpensInsideNotchInsteadOfLeavingTools() {
    let shelf = DropPopupController(store: ParcelStore(persist: false))
    shelf.summon()
    shelf.showModule(.launcher)
    shelf.showModule(.parcel)
    XCTAssertTrue(shelf.toolsVisible)
    XCTAssertEqual(shelf.activeModule, .parcel)
    shelf.dismiss()
  }

  @MainActor func testHoveringCollapsedNotchOpensDashboardImmediately() {
    let store = ParcelStore(persist: false)
    let shelf = DropPopupController(store: store)
    shelf.restoreResident()
    XCTAssertTrue(shelf.parkedInMenuBar)
    XCTAssertFalse(shelf.expanded)
    shelf.courierHoverChanged(true)
    XCTAssertTrue(shelf.expanded)
    XCTAssertTrue(shelf.toolsVisible)
    XCTAssertEqual(shelf.activeModule, .dashboard)
    shelf.dismiss()
  }

  @MainActor func testWidgetSizesPinsAndOrderPersist() throws {
    let suite = "NotchWidgetTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let widgets = NotchWidgetStore(defaults: defaults)
    widgets.resize(.parcel, to: .fourByFour)
    let wasPinned = widgets.pinned.contains { $0.kind == .parcel }
    widgets.togglePinned(.parcel)
    widgets.move(.parcel, before: .music)
    let restored = NotchWidgetStore(defaults: defaults)
    XCTAssertEqual(restored.widgets.first?.kind, .parcel)
    XCTAssertEqual(restored.widgets.first?.size, .fourByFour)
    XCTAssertEqual(restored.widgets.first?.pinned, !wasPinned)
  }

  @MainActor func testWidgetsPackIntoWholePagesAndMusicDefaultsToFullPage() throws {
    let suite = "NotchWidgetPages-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let widgets = NotchWidgetStore(defaults: defaults)
    XCTAssertEqual(widgets.widgets.first(where: { $0.kind == .music })?.size, .fourByFour)
    XCTAssertGreaterThan(widgets.pages.count, 1)
    for page in widgets.pages {
      XCTAssertLessThanOrEqual(page.reduce(0) { $0 + $1.size.columns * $1.size.rows }, 16)
    }
    XCTAssertEqual(Set(widgets.pages.flatMap { $0 }.map(\.kind)), Set(NotchWidgetKind.allCases))
  }

  @MainActor func testMediaRefreshNeverBlocksTheNotch() {
    let tools = NotchToolStore(defaults: .standard)
    let started = ProcessInfo.processInfo.systemUptime
    tools.refreshMedia()
    XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 0.1)
  }
}

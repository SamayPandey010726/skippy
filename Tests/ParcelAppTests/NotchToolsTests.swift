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
    widgets.move(.music, before: .parcel)
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
  @MainActor func testSearchPreservesLiteralPlusAmpersandAndUnicode() throws {
    let url = try XCTUnwrap(NotchToolStore.searchURL(for: " C++ & café "))
    XCTAssertTrue(url.absoluteString.contains("C%2B%2B"))
    XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "C++ & café")
    XCTAssertNil(NotchToolStore.searchURL(for: "  "))
  }

  func testDownloadListReadsRecentFilesAndSkipsDirectories() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: root.appendingPathComponent("Folder"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    for i in 0..<14 {
      let file = root.appendingPathComponent("File-\(i)")
      try Data().write(to: file)
      try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(i + 1))], ofItemAtPath: file.path)
    }
    XCTAssertEqual(NotchToolStore.recentDownloads(in: root).map(\.lastPathComponent), (2...13).reversed().map { "File-\($0)" })
  }

  @MainActor func testScreenshotSequenceJoinsAtFullWidthAndCanBeCleared() throws {
    let store = NotchToolStore(defaults: .standard)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for (index, size) in [NSSize(width: 60, height: 20), NSSize(width: 40, height: 30)].enumerated() {
      let buffer = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height),
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      buffer.setFillColor((index == 0 ? NSColor.red : NSColor.blue).cgColor)
      buffer.fill(CGRect(origin: .zero, size: size))
      let image = try XCTUnwrap(buffer.makeImage())
      let url = root.appendingPathComponent("test-\(index).png")
      try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: url)
      store.addCapture(from: url)
    }
    XCTAssertEqual(store.captures.count, 2)
    store.copyCombinedCaptures()
    let joined = try XCTUnwrap(NSImage(pasteboard: .general))
    XCTAssertEqual(joined.size.width, 60, accuracy: 1)
    XCTAssertEqual(joined.size.height, 50, accuracy: 1)
    store.clearCaptures()
    XCTAssertTrue(store.captures.isEmpty)
  }

  @MainActor func testLocalPlaybackLoadsBundledMacAudio() throws {
    let store = NotchToolStore(defaults: .standard)
    let sound = URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")
    store.playAudio(at: sound)
    XCTAssertEqual(store.audioTitle, "Glass")
    if store.isPlaying {
      store.toggleAudio()
      XCTAssertFalse(store.isPlaying)
      XCTAssertEqual(store.status, "Paused")
    } else {
      XCTAssertEqual(store.status, "Audio output unavailable")
    }
  }

  func testSampledPixelRoundsToNearestSRGBByte() {
    XCTAssertEqual(NotchToolStore.hexValue(for: NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)), "#FF8000")
  }

}

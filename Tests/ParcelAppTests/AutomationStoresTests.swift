import XCTest
@testable import ParcelApp
import ParcelCore

@MainActor final class AutomationStoresTests: XCTestCase {
  func testPresetsPersistNormalizeAndRemainEditable() {
    let defaults = isolatedDefaults()
    let store = TransformPresetStore(defaults: defaults)
    var recipe = ImageRecipe()
    recipe.quality = 4
    recipe.maximumDimension = 123
    store.addImage(name: "  Tiny web  ", recipe: recipe)
    let created = store.imagePresets.last!
    XCTAssertEqual(created.name, "Tiny web")
    XCTAssertEqual(created.recipe.quality, 1)
    XCTAssertEqual(created.recipe.maximumDimension, 2400)

    var edited = created
    edited.name = "Edited"
    edited.recipe.maximumDimension = 1200
    store.update(edited)
    let reloaded = TransformPresetStore(defaults: defaults)
    XCTAssertEqual(reloaded.imagePresets.last?.name, "Edited")
    XCTAssertEqual(reloaded.imagePresets.last?.recipe.maximumDimension, 1200)
  }

  func testRecentActionsAreBoundedAndPrioritizeAvailableConversions() {
    let defaults = isolatedDefaults()
    let history = RecentActionStore(defaults: defaults)
    history.record(id: "convert.png", title: "PNG", symbol: "photo", at: Date(timeIntervalSince1970: 1))
    history.record(id: "convert.jpeg", title: "JPEG", symbol: "photo", at: Date(timeIntervalSince1970: 2))
    XCTAssertEqual(history.prioritize([.heic, .png, .jpeg]), [.jpeg, .png, .heic])
    XCTAssertTrue(history.isRecent(.jpeg))
    for index in 0..<12 {
      history.record(id: "action.\(index)", title: "Action", symbol: "bolt")
    }
    XCTAssertEqual(history.actions.count, 8)
  }

  func testDisplayAnchorsStayIndependentAndRejectOffscreenValues() {
    let defaults = isolatedDefaults()
    let positions = CourierDisplayPositions(defaults: defaults)
    let left = CGRect(x: -1000, y: 0, width: 1000, height: 800)
    let right = CGRect(x: 0, y: 0, width: 1200, height: 900)
    positions.save(CGPoint(x: -100, y: 700), displayID: "left", separate: true)
    positions.save(CGPoint(x: 1100, y: 800), displayID: "right", separate: true)
    XCTAssertEqual(positions.anchor(displayID: "left", frame: left, separate: true), CGPoint(x: -100, y: 700))
    XCTAssertEqual(positions.anchor(displayID: "right", frame: right, separate: true), CGPoint(x: 1100, y: 800))
    XCTAssertNil(positions.anchor(displayID: "left", frame: right, separate: true))
    positions.reset()
    XCTAssertNil(positions.anchor(displayID: "right", frame: right, separate: true))
  }

  private func isolatedDefaults() -> UserDefaults {
    let suite = "ParcelAutomationTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
  }
}

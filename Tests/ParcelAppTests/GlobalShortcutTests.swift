import Carbon
import XCTest
@testable import ParcelApp

final class GlobalShortcutTests: XCTestCase {
  func testDefaultUsesLowConflictThreeModifierCombination() {
    let shortcut = GlobalShortcut.defaultShortcut
    XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_P))
    XCTAssertEqual(shortcut.modifiers, UInt32(controlKey | optionKey | cmdKey))
    XCTAssertEqual(shortcut.displayName, "⌃⌥⌘P")
    XCTAssertEqual(shortcut.spokenName, "Control + Option + Command + P")
    XCTAssertTrue(shortcut.isValid)
  }

  func testDisplayOrderMatchesMacConvention() {
    let shortcut = GlobalShortcut(
      keyCode: UInt32(kVK_ANSI_K),
      modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey), keyLabel: "k")
    XCTAssertEqual(shortcut.displayName, "⌃⌥⇧⌘K")
  }

  func testShortcutRequiresAtLeastTwoModifiers() {
    XCTAssertFalse(GlobalShortcut(
      keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey), keyLabel: "P").isValid)
    XCTAssertTrue(GlobalShortcut(
      keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | optionKey), keyLabel: "P").isValid)
  }

  func testShortcutPersistsAndInvalidStoredValueFallsBack() throws {
    let suite = "GlobalShortcutTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let shortcut = GlobalShortcut(
      keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | shiftKey | cmdKey), keyLabel: "K")
    shortcut.save(defaults: defaults)
    XCTAssertEqual(GlobalShortcut.load(defaults: defaults), shortcut)
    defaults.set(Int(cmdKey), forKey: "parcel.globalShortcut.modifiers")
    XCTAssertEqual(GlobalShortcut.load(defaults: defaults), .defaultShortcut)
  }

  func testTutorialCoversBeginningToShortcutSetup() {
    XCTAssertEqual(OnboardingStep.allCases.count, 6)
    XCTAssertEqual(OnboardingStep.allCases.first, .welcome)
    XCTAssertEqual(OnboardingStep.allCases.last, .shortcut)
    XCTAssertTrue(OnboardingStep.allCases.contains(.defaults))
  }

  @MainActor func testCarbonHotKeyEventInvokesInstalledAction() async throws {
    let invoked = expectation(description: "Global shortcut action invoked")
    GlobalShortcutManager.shared.install { invoked.fulfill() }
    var event: EventRef?
    XCTAssertEqual(CreateEvent(
      nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), GetCurrentEventTime(),
      EventAttributes(kEventAttributeNone), &event), noErr)
    let createdEvent = try XCTUnwrap(event)
    XCTAssertEqual(SendEventToEventTarget(createdEvent, GetApplicationEventTarget()), noErr)
    await fulfillment(of: [invoked], timeout: 1)
  }

  @MainActor func testCourierBindingsMatchPersistAndRejectDuplicates() throws {
    let suite = "CourierShortcutTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = CourierShortcutStore(defaults: defaults)
    XCTAssertEqual(store.binding(for: .nextFile).displayName, "⇥")
    XCTAssertEqual(store.binding(for: .filters).displayName, "⇧/")
    XCTAssertEqual(store.binding(for: .clipboard).displayName, "⌥C")
    XCTAssertEqual(store.binding(for: .tools).displayName, "⌥T")
    XCTAssertEqual(store.binding(for: .ocr).displayName, "⇧⌘O")
    let custom = CourierKeyBinding(keyCode: UInt16(kVK_ANSI_J), modifiers: NSEvent.ModifierFlags.command.rawValue, keyLabel: "J")
    XCTAssertTrue(store.update(.pack, binding: custom))
    XCTAssertFalse(store.update(.copy, binding: custom))
    XCTAssertEqual(CourierShortcutStore(defaults: defaults).binding(for: .pack), custom)
  }
}

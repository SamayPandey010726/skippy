import XCTest
@testable import ParcelApp
import ParcelCore

final class ParcelNameSuggesterTests: XCTestCase {
  func testUsesMeaningfulSharedPrefixWithoutReadingFileContents() {
    let items = ["Launch hero.png", "Launch hero mobile.png"].map {
      ParcelItem(sourcePath: "/private/\($0)", displayName: $0)
    }
    XCTAssertEqual(ParcelNameSuggester.suggest(for: items), "Launch hero · 2 files")
  }

  func testFallsBackToTypeAndStableLocalDate() {
    let items = ["IMG_1.jpg", "DSC_2.png"].map {
      ParcelItem(sourcePath: "/private/\($0)", displayName: $0)
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = Date(timeIntervalSince1970: 1_767_225_600)
    XCTAssertEqual(ParcelNameSuggester.suggest(for: items, date: date, calendar: calendar), "Images · Jan 1")
  }

  func testEmptyParcelHasNoSuggestion() {
    XCTAssertNil(ParcelNameSuggester.suggest(for: []))
  }
}

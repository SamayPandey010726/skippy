import XCTest
@testable import ParcelCore

final class FileSearchTests: XCTestCase {
  private var calendar: Calendar {
    var result = Calendar(identifier: .gregorian)
    result.timeZone = TimeZone(secondsFromGMT: 19800)!
    return result
  }
  private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))! }
  private func item(_ name: String, size: Int64 = 100, day: Int = 17, folder: Bool = false) -> ParcelItem {
    var result = ParcelItem(sourcePath: "/fixture/" + name, displayName: name, isDirectory: folder, byteCount: size)
    result.addedAt = calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    return result
  }
  func testNaturalExcelOrNumbersQueryUnionsTypesIncludingNumbersPackages() {
    let query = ParcelFileQuery("All excel files or number files", now: now, calendar: calendar)
    XCTAssertTrue(query.matches(item("Budget.xlsx")))
    XCTAssertTrue(query.matches(item("Budget.numbers", folder: true)))
    XCTAssertFalse(query.matches(item("Budget.pdf")))
    XCTAssertFalse(query.matches(item("Budget.csv")))
  }
  func testUploadedOrdinalUsesAddedDateInCurrentMonthAndExplainsIt() {
    let query = ParcelFileQuery("File uploaded on 17th", now: now, calendar: calendar)
    XCTAssertEqual(query.dateDescription, "Added 17 Oct 2026")
    XCTAssertTrue(query.matches(item("Report.xlsx")))
    XCTAssertFalse(query.matches(item("Report.xlsx", day: 16)))
    var old = item("Old.xlsx")
    old.addedAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: 17))!
    XCTAssertFalse(query.matches(old))
  }
  func testISODateRelativeDaysAndInvalidDatesAreNotSilentlyGuessed() {
    XCTAssertTrue(ParcelFileQuery("added on 2026-10-16", now: now, calendar: calendar).matches(item("Note.txt", day: 16)))
    XCTAssertTrue(ParcelFileQuery("added yesterday", now: now, calendar: calendar).matches(item("Note.txt", day: 16)))
    XCTAssertFalse(ParcelFileQuery("today", now: now, calendar: calendar).matches(item("Note.txt", day: 16)))
    let invalid = ParcelFileQuery("uploaded on 2026-02-31", now: now, calendar: calendar)
    XCTAssertNotNil(invalid.warning)
    XCTAssertFalse(invalid.matches(item("Note.txt")))
  }
  func testNaturalSizeAndFilenameConstraintsCombineWithoutChangingPayloads() {
    let query = ParcelFileQuery("pdf over 1 MB under 10 MB invoice", now: now, calendar: calendar)
    XCTAssertTrue(query.matches(item("Invoice.pdf", size: 2_000_000)))
    XCTAssertFalse(query.matches(item("Invoice.pdf", size: 1_000_000)))
    XCTAssertFalse(query.matches(item("Invoice.pdf", size: 10_000_000)))
    XCTAssertFalse(query.matches(item("Other.pdf", size: 2_000_000)))
    XCTAssertFalse(query.matches(item("Invoice.png", size: 2_000_000)))
  }
  func testQuotedNamesStayLiteralAndPreparedSizesAreSearched() {
    var image = item("Images uploaded on 17th.png", size: 20_000_000)
    image.preparedBytes = 500_000
    let query = ParcelFileQuery("\"Images uploaded on 17th\" under 1 mb", now: now, calendar: calendar)
    XCTAssertTrue(query.matches(image))
    XCTAssertNil(query.addedInterval)
  }
  func testClickableTypeSizeAndDateFiltersIntersectTextQuery() {
    let query = ParcelFileQuery("budget", type: .spreadsheets, size: .over10MB, added: .today, now: now, calendar: calendar)
    XCTAssertTrue(query.matches(item("Budget.csv", size: 12_000_000)))
    XCTAssertFalse(query.matches(item("Budget.csv", size: 12_000_000, day: 16)))
    XCTAssertFalse(query.matches(item("Budget.csv", size: 100)))
    XCTAssertFalse(query.matches(item("Budget.pdf", size: 12_000_000)))
  }
  func testDateEndIsExclusiveAndLastWeekContainsSevenCalendarDays() {
    let query = ParcelFileQuery("last 7 days", now: now, calendar: calendar)
    XCTAssertTrue(query.matches(item("A.txt", day: 11)))
    XCTAssertFalse(query.matches(item("A.txt", day: 10)))
    XCTAssertFalse(query.matches(item("A.txt", day: 18)))
  }
}

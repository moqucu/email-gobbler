import Foundation
import XCTest
@testable import SchoologyMailPreview
import SchoologyDomain

final class NumbersFormattingTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> CalendarDate {
        try! CalendarDate(year: year, month: month, day: day)
    }

    private func display(_ format: NumbersCellFormat, _ formatted: String?) -> NumbersCellDisplay {
        NumbersCellDisplay(format: format, formattedValue: formatted)
    }

    private func plan(_ action: WorkbookUpdatePlan.Action, _ cells: [PlannedCell], weekEnd: CalendarDate? = nil) -> WorkbookUpdatePlan {
        WorkbookUpdatePlan(action: action, weekEnd: weekEnd ?? date(2026, 9, 21), cells: cells, ignoredMissingCourses: [])
    }

    private let twoCourseCells = [
        PlannedCell(column: 2, value: "0.8794"), PlannedCell(column: 3, value: "B+"),
        PlannedCell(column: 4, value: nil), PlannedCell(column: 5, value: nil),
    ]

    private func assertFormatError<T>(_ expected: NumbersFormatError, _ expression: @autoclosure () throws -> T,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? NumbersFormatError, expected, file: file, line: line)
        }
    }

    // MARK: - Format names reported by Numbers

    func testFormatNamesFromNumbersAreRecognized() {
        XCTAssertEqual(NumbersCellFormat(appleScriptName: "date and time"), .dateAndTime)
        XCTAssertEqual(NumbersCellFormat(appleScriptName: "percent"), .percent)
        XCTAssertEqual(NumbersCellFormat(appleScriptName: "automatic"), .automatic)
        XCTAssertEqual(NumbersCellFormat(appleScriptName: "number"), .other("number"))
    }

    // MARK: - Date display

    func testExpectedDateDisplayIsMonthDayTwoDigitYear() {
        XCTAssertEqual(expectedDateDisplay(date(2026, 9, 21)), "9/21/26")
        XCTAssertEqual(expectedDateDisplay(date(2026, 3, 9)), "3/9/26")
        XCTAssertEqual(expectedDateDisplay(date(2026, 12, 31)), "12/31/26")
        XCTAssertEqual(expectedDateDisplay(date(2005, 1, 2)), "1/2/05")
    }

    // MARK: - Where a new row inherits its formatting

    func testInsertAboveAnOlderDatedRowInheritsFromThatRow() throws {
        let rows = [(row: 2, date: date(2026, 9, 14)), (row: 3, date: date(2026, 9, 7))]
        XCTAssertEqual(try rowInsertion(for: .insert(row: 2), datedRows: rows),
                       RowInsertion(command: "add row above row 2 of t", templateRow: 2))
    }

    func testInsertAfterTheOldestDatedRowInheritsFromTheRowAbove() throws {
        let rows = [(row: 2, date: date(2026, 9, 28)), (row: 3, date: date(2026, 9, 21))]
        XCTAssertEqual(try rowInsertion(for: .insert(row: 4), datedRows: rows),
                       RowInsertion(command: "add row below row 3 of t", templateRow: 3))
    }

    func testReplacementKeepsTheRowAndChecksItsOwnFormatting() throws {
        let rows = [(row: 2, date: date(2026, 9, 21))]
        XCTAssertEqual(try rowInsertion(for: .replace(row: 2), datedRows: rows),
                       RowInsertion(command: "", templateRow: 2))
    }

    func testInsertIntoASheetWithoutDatedRowsHasNoFormattingTemplate() {
        assertFormatError(.noTemplateRow, try rowInsertion(for: .insert(row: 2), datedRows: []))
    }

    // MARK: - Formatting required before writing

    func testFormattedTemplateRowIsAccepted() throws {
        let template = [
            display(.dateAndTime, "9/14/26"), display(.percent, "91%"), display(.automatic, "A-"),
            display(.percent, nil), display(.automatic, nil),
        ]
        XCTAssertNoThrow(try validateTemplateFormats(template, plan: plan(.insert(row: 2), twoCourseCells), row: 2))
    }

    func testAutomaticDateWithTimeIsRejected() {
        let template = [
            display(.automatic, "9/21/26 12:00 AM"), display(.percent, "88%"), display(.automatic, "B+"),
            display(.percent, "75%"), display(.automatic, "C"),
        ]
        assertFormatError(.dateNotFormatted(row: 2),
                          try validateTemplateFormats(template, plan: plan(.replace(row: 2), twoCourseCells), row: 2))
    }

    func testExplicitDateFormatShowingATimeIsRejected() {
        let template = [
            display(.dateAndTime, "9/14/26 12:00 AM"), display(.percent, "91%"), display(.automatic, "A-"),
            display(.percent, "75%"), display(.automatic, "C"),
        ]
        assertFormatError(.dateNotFormatted(row: 3),
                          try validateTemplateFormats(template, plan: plan(.insert(row: 4), twoCourseCells), row: 3))
    }

    func testAutomaticPercentageColumnIsRejected() {
        let template = [
            display(.dateAndTime, "9/14/26"), display(.automatic, "0.8794"), display(.automatic, "B+"),
            display(.percent, "75%"), display(.automatic, "C"),
        ]
        assertFormatError(.percentageNotFormatted(row: 2, column: 2),
                          try validateTemplateFormats(template, plan: plan(.insert(row: 2), twoCourseCells), row: 2))
    }

    func testPercentageShowingDecimalsIsRejected() {
        let template = [
            display(.dateAndTime, "9/14/26"), display(.percent, "91%"), display(.automatic, "A-"),
            display(.percent, "87.94%"), display(.automatic, "B+"),
        ]
        assertFormatError(.percentageNotFormatted(row: 2, column: 4),
                          try validateTemplateFormats(template, plan: plan(.insert(row: 2), twoCourseCells), row: 2))
    }

    func testTemplateMissingAColumnIsRejected() {
        let template = [display(.dateAndTime, "9/14/26"), display(.percent, "91%"), display(.automatic, "A-")]
        assertFormatError(.percentageNotFormatted(row: 2, column: 4),
                          try validateTemplateFormats(template, plan: plan(.insert(row: 2), twoCourseCells), row: 2))
    }

    // MARK: - Display checked after saving

    func testWrittenRowShowingDateAndWholePercentsIsAccepted() throws {
        let written = [
            display(.dateAndTime, "9/21/26"), display(.percent, "88%"), display(.automatic, "B+"),
            display(.percent, nil), display(.automatic, nil),
        ]
        XCTAssertNoThrow(try validateWrittenDisplay(written, plan: plan(.insert(row: 2), twoCourseCells), row: 2))
    }

    func testWrittenPercentageMayRoundUpOrDown() throws {
        let cells = [PlannedCell(column: 2, value: "0.875"), PlannedCell(column: 3, value: "B+"),
                     PlannedCell(column: 4, value: "0.6949"), PlannedCell(column: 5, value: "D+")]
        let written = [
            display(.dateAndTime, "9/21/26"), display(.percent, "88%"), display(.automatic, "B+"),
            display(.percent, "69%"), display(.automatic, "D+"),
        ]
        XCTAssertNoThrow(try validateWrittenDisplay(written, plan: plan(.replace(row: 3), cells), row: 3))
    }

    func testWrittenDateShowingTimestampIsRejected() {
        let written = [
            display(.automatic, "9/21/26 12:00 AM"), display(.percent, "88%"), display(.automatic, "B+"),
            display(.percent, nil), display(.automatic, nil),
        ]
        assertFormatError(.writtenDateDisplay(row: 2, expected: "9/21/26", actual: "9/21/26 12:00 AM"),
                          try validateWrittenDisplay(written, plan: plan(.insert(row: 2), twoCourseCells), row: 2))
    }

    func testWrittenPercentageShowingFractionIsRejected() {
        let written = [
            display(.dateAndTime, "9/21/26"), display(.automatic, "0.8794"), display(.automatic, "B+"),
            display(.percent, nil), display(.automatic, nil),
        ]
        assertFormatError(.writtenPercentageDisplay(row: 2, column: 2, actual: "0.8794"),
                          try validateWrittenDisplay(written, plan: plan(.insert(row: 2), twoCourseCells), row: 2))
    }

    func testWrittenPercentageShowingDecimalsIsRejected() {
        let written = [
            display(.dateAndTime, "9/21/26"), display(.percent, "87.94%"), display(.automatic, "B+"),
            display(.percent, nil), display(.automatic, nil),
        ]
        assertFormatError(.writtenPercentageDisplay(row: 2, column: 2, actual: "87.94%"),
                          try validateWrittenDisplay(written, plan: plan(.insert(row: 2), twoCourseCells), row: 2))
    }

    func testWrittenPercentageForADifferentValueIsRejected() {
        let written = [
            display(.dateAndTime, "9/21/26"), display(.percent, "86%"), display(.automatic, "B+"),
            display(.percent, nil), display(.automatic, nil),
        ]
        assertFormatError(.writtenPercentageDisplay(row: 2, column: 2, actual: "86%"),
                          try validateWrittenDisplay(written, plan: plan(.insert(row: 2), twoCourseCells), row: 2))
    }
}

import Foundation
import XCTest
import EmailGobblerCore
@testable import SchoologyGrades

final class GradesWorkbookPlannerTests: XCTestCase {
    private func date(_ day: Int) -> CalendarDate { try! CalendarDate(year: 2026, month: 9, day: day) }
    private func dec(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    private func extraction(_ courses: [ExtractedCourse], weekEnd: Int = 28) -> SchoologyWeeklyExtraction {
        SchoologyWeeklyExtraction(
            reportingPeriod: ReportingPeriod(start: date(weekEnd - 7), end: date(weekEnd)),
            students: [ExtractedStudent(studentLabel: "Student Alpha", courses: courses)]
        )
    }

    private func course(_ label: String, _ grade: ExtractedOverallGrade) -> ExtractedCourse {
        ExtractedCourse(courseLabel: label, gradingPeriodText: nil, overallGrade: grade)
    }

    private func header(_ names: [String]) -> [SheetCell] {
        names.map { SheetCell(value: .text($0), formatted: $0.isEmpty ? nil : $0, format: .automatic) }
    }

    private func datedRow(_ day: Int, width: Int) -> [SheetCell] {
        [SheetCell(value: .date(date(day)), formatted: "9/\(day)/26", format: .dateAndTime)]
            + Array(repeating: SheetCell(value: .empty, formatted: nil, format: .automatic), count: width - 1)
    }

    private func sheet(_ names: [String], dated days: [Int], trailingEmpty: Int = 0) -> SheetSnapshot {
        let blank = Array(repeating: SheetCell(value: .empty, formatted: nil, format: .automatic), count: names.count)
        return SheetSnapshot(rows: [header(names)] + days.map { datedRow($0, width: names.count) }
                             + Array(repeating: blank, count: trailingEmpty))
    }

    private let twoCourses = ["Date", "Algebra 2", "", "AP Biology", ""]

    private func assertPlanError<T>(_ expected: GradesWorkbookError, _ expression: @autoclosure () throws -> T,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? GradesWorkbookError, expected, file: file, line: line)
        }
    }

    func testNewWeekMapsCoursePrefixesToPercentageAndLetterCells() throws {
        let report = extraction([
            course("Algebra 2 - 2310: Teacher p6 T1", .present(letter: "B+", percentage: dec("87.94"))),
            course("AP Biology - 3120: Teacher p5 T1", .present(letter: "D+", percentage: Decimal(69))),
            course("Unmapped Club: Section 1", .missing(.dash)),
        ])
        let plan = try planGradesWorkbookUpdate(report: report, studentLabel: "Student Alpha",
                                                sheet: sheet(twoCourses, dated: [21, 14]))
        XCTAssertEqual(plan.update, SheetUpdatePlan(
            placement: .insertAbove(row: 2),
            rows: [PlannedRow(
                values: [1: .date(date(28)), 2: .number(dec("0.8794")), 3: .text("B+"), 4: .number(dec("0.69")), 5: .text("D+")],
                displays: [1: .exact("9/28/26"), 2: .wholePercent(of: dec("0.8794")), 4: .wholePercent(of: dec("0.69"))]
            )],
            templateRequirements: [1: .dateOnly(.monthDayShortYear), 2: .wholePercent, 4: .wholePercent]
        ))
        XCTAssertEqual(plan.ignoredMissingCourses, ["Unmapped Club: Section 1"])
    }

    func testExistingWeekIsReplacedAndMissingGradesAreBlank() throws {
        let report = extraction([
            course("Algebra 2 - 2310: Teacher", .missing(.dash)),
            course("AP Biology - 3120: Teacher", .present(letter: "A", percentage: nil)),
        ])
        let plan = try planGradesWorkbookUpdate(report: report, studentLabel: "Student Alpha",
                                                sheet: sheet(twoCourses, dated: [28, 21]))
        XCTAssertEqual(plan.update.placement, .replace(row: 2))
        XCTAssertEqual(plan.update.rows.first?.values,
                       [1: .date(date(28)), 2: .empty, 3: .empty, 4: .empty, 5: .text("A")])
        XCTAssertEqual(plan.update.rows.first?.displays, [1: .exact("9/28/26")])
    }

    func testMiddleWeekIsInsertedAboveTheNextOlderWeek() throws {
        let report = extraction([course("Algebra 2 - 1: T", .present(letter: "A", percentage: nil)),
                                 course("AP Biology - 2: T", .present(letter: "A", percentage: nil))], weekEnd: 21)
        let plan = try planGradesWorkbookUpdate(report: report, studentLabel: "Student Alpha",
                                                sheet: sheet(twoCourses, dated: [28, 14]))
        XCTAssertEqual(plan.update.placement, .insertAbove(row: 3))
    }

    func testOldestWeekIsInsertedBelowTheOldestRow() throws {
        let report = extraction([course("Algebra 2 - 1: T", .present(letter: "A", percentage: nil)),
                                 course("AP Biology - 2: T", .present(letter: "A", percentage: nil))], weekEnd: 14)
        let plan = try planGradesWorkbookUpdate(report: report, studentLabel: "Student Alpha",
                                                sheet: sheet(twoCourses, dated: [28, 21], trailingEmpty: 3))
        XCTAssertEqual(plan.update.placement, .insertBelow(row: 3))
    }

    func testSheetWithoutDatedRowsHasNoFormattingTemplate() {
        let report = extraction([course("Algebra 2 - 1: T", .present(letter: "A", percentage: nil)),
                                 course("AP Biology - 2: T", .present(letter: "A", percentage: nil))])
        assertPlanError(.noTemplateRow, try planGradesWorkbookUpdate(report: report, studentLabel: "Student Alpha",
                                                                     sheet: sheet(twoCourses, dated: [], trailingEmpty: 3)))
    }

    func testDateRowsMustBeContiguousAndNewestFirst() {
        let report = extraction([course("Algebra 2 - 1: T", .present(letter: "A", percentage: nil)),
                                 course("AP Biology - 2: T", .present(letter: "A", percentage: nil))])
        assertPlanError(.invalidDateRows, try planGradesWorkbookUpdate(report: report, studentLabel: "Student Alpha",
                                                                       sheet: sheet(twoCourses, dated: [14, 21])))
        var rows = sheet(twoCourses, dated: [21, 14]).rows
        rows.insert(header(["", "", "", "", ""]).map { _ in SheetCell(value: .empty, formatted: nil, format: .automatic) }, at: 2)
        assertPlanError(.invalidDateRows, try planGradesWorkbookUpdate(report: report, studentLabel: "Student Alpha",
                                                                       sheet: SheetSnapshot(rows: rows)))
    }

    func testUnmappedGradedCourseStudentMismatchAndHeadersStopThePlan() {
        let unknown = extraction([course("Unknown Course - 1234: Teacher", .present(letter: "A", percentage: nil))])
        let snapshot = sheet(["Date", "Algebra 2", ""], dated: [21])
        assertPlanError(.unmappedGradedCourse("Unknown Course - 1234: Teacher"),
                        try planGradesWorkbookUpdate(report: unknown, studentLabel: "Student Alpha", sheet: snapshot))
        let algebra = extraction([course("Algebra 2 - 2310: Teacher", .present(letter: "A", percentage: nil))])
        assertPlanError(.studentNotFound("Student Beta"),
                        try planGradesWorkbookUpdate(report: algebra, studentLabel: "Student Beta", sheet: snapshot))
        assertPlanError(.invalidHeaders,
                        try planGradesWorkbookUpdate(report: algebra, studentLabel: "Student Alpha",
                                                     sheet: sheet(["Week", "Algebra 2", ""], dated: [21])))
        assertPlanError(.missingWorkbookCourse("AP Biology"),
                        try planGradesWorkbookUpdate(report: algebra, studentLabel: "Student Alpha",
                                                     sheet: sheet(twoCourses, dated: [21])))
    }
}

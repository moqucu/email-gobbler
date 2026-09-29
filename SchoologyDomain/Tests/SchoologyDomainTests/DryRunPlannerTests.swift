import Foundation
import XCTest
@testable import SchoologyMailPreview
import SchoologyDomain

final class DryRunPlannerTests: XCTestCase {
    private func date(_ day: Int) throws -> CalendarDate {
        try CalendarDate(year: 2026, month: 9, day: day)
    }

    private func extraction(_ courses: [ExtractedCourse]) throws -> SchoologyWeeklyExtraction {
        SchoologyWeeklyExtraction(
            reportingPeriod: ReportingPeriod(start: try date(21), end: try date(28)),
            students: [ExtractedStudent(studentLabel: "Student Alpha", courses: courses)]
        )
    }

    private func course(_ label: String, _ grade: ExtractedOverallGrade) -> ExtractedCourse {
        ExtractedCourse(courseLabel: label, gradingPeriodText: nil, overallGrade: grade)
    }

    func testNewWeekMapsCoursePrefixesToPercentageAndLetterCells() throws {
        let report = try extraction([
            course("Algebra 2 - 2310: Teacher p6 T1", .present(letter: "B+", percentage: Decimal(string: "87.94"))),
            course("AP Biology - 3120: Teacher p5 T1", .present(letter: "D+", percentage: Decimal(69))),
            course("Unmapped Club: Section 1", .missing(.dash)),
        ])
        let snapshot = WorkbookSheetSnapshot(
            headers: ["Date", "Algebra 2", "", "AP Biology", ""],
            datedRows: [(row: 2, date: try date(21)), (row: 3, date: try date(14))]
        )
        let plan = try planWorkbookUpdate(report: report, studentLabel: "Student Alpha", sheet: snapshot)
        XCTAssertEqual(plan.action, .insert(row: 2))
        XCTAssertEqual(plan.cells, [
            PlannedCell(column: 2, value: "0.8794"), PlannedCell(column: 3, value: "B+"),
            PlannedCell(column: 4, value: "0.69"), PlannedCell(column: 5, value: "D+"),
        ])
        XCTAssertEqual(plan.ignoredMissingCourses, ["Unmapped Club: Section 1"])
    }

    func testExistingWeekIsReplacementAndMissingAcademicGradeIsBlank() throws {
        let report = try extraction([
            course("Algebra 2 - 2310: Teacher", .missing(.dash)),
            course("AP Biology - 3120: Teacher", .present(letter: "A", percentage: nil)),
        ])
        let snapshot = WorkbookSheetSnapshot(
            headers: ["Date", "Algebra 2", "", "AP Biology", ""],
            datedRows: [(row: 2, date: try date(28)), (row: 3, date: try date(21))]
        )
        let plan = try planWorkbookUpdate(report: report, studentLabel: "Student Alpha", sheet: snapshot)
        XCTAssertEqual(plan.action, .replace(row: 2))
        XCTAssertEqual(plan.cells, [
            PlannedCell(column: 2, value: nil), PlannedCell(column: 3, value: nil),
            PlannedCell(column: 4, value: nil), PlannedCell(column: 5, value: "A"),
        ])
    }

    func testUnmappedPresentGradeStopsThePlan() throws {
        let report = try extraction([course("Unknown Course - 1234: Teacher", .present(letter: "A", percentage: nil))])
        let snapshot = WorkbookSheetSnapshot(headers: ["Date", "Algebra 2", ""], datedRows: [])
        XCTAssertThrowsError(try planWorkbookUpdate(report: report, studentLabel: "Student Alpha", sheet: snapshot))
    }

    func testStudentMismatchStopsThePlan() throws {
        let report = try extraction([course("Algebra 2 - 2310: Teacher", .present(letter: "A", percentage: nil))])
        let snapshot = WorkbookSheetSnapshot(headers: ["Date", "Algebra 2", ""], datedRows: [])
        XCTAssertThrowsError(try planWorkbookUpdate(report: report, studentLabel: "Student Beta", sheet: snapshot))
    }
}

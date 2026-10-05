import Foundation
import XCTest
import EmailGobblerCore
@testable import SchoologyGrades
@testable import EtradeDividends

final class UseCaseRoutingTests: XCTestCase {
    private func target(_ sheet: String) -> SheetTarget {
        SheetTarget(workbook: URL(fileURLWithPath: "/tmp/Grades.numbers"), sheetName: sheet)
    }

    /// A grades sheet whose headers match one fixture student's courses, with one dated row.
    private func gradesSheet(for student: String) throws -> SheetSnapshot {
        let extraction = try parseSchoologyWeeklyEmail(html: try SchoologyFixtures.baselineHTML())
        let courses = try XCTUnwrap(extraction.students.first { $0.studentLabel == student }).courses
        let names = ["Date"] + courses.flatMap { [$0.courseLabel, ""] }
        let header = names.map { SheetCell(value: .text($0), formatted: $0.isEmpty ? nil : $0, format: .automatic) }
        let dated = [SheetCell(value: .date(try CalendarDate(year: 2026, month: 3, day: 2)), formatted: "3/2/26", format: .dateAndTime)]
            + (1..<names.count).map { column in
                column.isMultiple(of: 2) ? SheetCell(value: .empty, formatted: nil, format: .automatic)
                                         : SheetCell(value: .empty, formatted: nil, format: .percent)
            }
        return SheetSnapshot(rows: [header, dated])
    }

    func testGradesUseCaseDeclaresOneTargetPerRoute() {
        let useCase = SchoologyGradesUseCase(routes: [StudentRoute(studentLabel: "Student Alpha", target: target("Alpha")),
                                                      StudentRoute(studentLabel: "Student Beta", target: target("Beta"))])
        XCTAssertEqual(useCase.targets, [target("Alpha"), target("Beta")])
        XCTAssertEqual(SchoologyGradesUseCase(routes: []).targets, [])
    }

    func testRoutedStudentIsPlannedAndOthersAreIgnoredWithANote() throws {
        let useCase = SchoologyGradesUseCase(routes: [StudentRoute(studentLabel: "Student Alpha", target: target("Alpha"))])
        let plan = try useCase.plan(html: try SchoologyFixtures.baselineHTML(),
                                    sheets: [target("Alpha"): try gradesSheet(for: "Student Alpha")])
        XCTAssertEqual(plan.targets.map(\.target), [target("Alpha")])
        XCTAssertEqual(plan.targets.first?.update.placement, .insertAbove(row: 2))
        XCTAssertTrue(plan.notes.contains("Students without a route: 1"), "\(plan.notes)")
    }

    func testEveryRoutedStudentGetsItsOwnTarget() throws {
        let useCase = SchoologyGradesUseCase(routes: [StudentRoute(studentLabel: "Student Alpha", target: target("Alpha")),
                                                      StudentRoute(studentLabel: "Student Beta", target: target("Beta"))])
        let plan = try useCase.plan(html: try SchoologyFixtures.baselineHTML(),
                                    sheets: [target("Alpha"): try gradesSheet(for: "Student Alpha"),
                                             target("Beta"): try gradesSheet(for: "Student Beta")])
        XCTAssertEqual(plan.targets.map(\.target), [target("Alpha"), target("Beta")])
        XCTAssertFalse(plan.notes.contains { $0.hasPrefix("Students without a route") })
    }

    func testRoutedStudentMissingFromTheEmailStopsThePlan() throws {
        let useCase = SchoologyGradesUseCase(routes: [StudentRoute(studentLabel: "Student Gamma", target: target("Gamma"))])
        XCTAssertThrowsError(try useCase.plan(html: try SchoologyFixtures.baselineHTML(),
                                              sheets: [target("Gamma"): try gradesSheet(for: "Student Alpha")])) { error in
            XCTAssertEqual(error as? GradesWorkbookError, .studentNotFound("Student Gamma"))
        }
    }

    func testTwoRoutesToOneSheetAreRejected() throws {
        let useCase = SchoologyGradesUseCase(routes: [StudentRoute(studentLabel: "Student Alpha", target: target("Shared")),
                                                      StudentRoute(studentLabel: "Student Beta", target: target("Shared"))])
        XCTAssertThrowsError(try useCase.plan(html: try SchoologyFixtures.baselineHTML(),
                                              sheets: [target("Shared"): try gradesSheet(for: "Student Alpha")])) { error in
            XCTAssertEqual(error as? SchoologyGradesUseCaseError, .duplicateTarget(target("Shared")))
        }
    }

    func testDividendsUseCaseHasOneOptionalTarget() {
        let ledger = SheetTarget(workbook: URL(fileURLWithPath: "/tmp/Ledger.numbers"), sheetName: "Sheet 1")
        XCTAssertEqual(EtradeDividendsUseCase(target: ledger).targets, [ledger])
        XCTAssertEqual(EtradeDividendsUseCase(target: nil).targets, [])
    }
}

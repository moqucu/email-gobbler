import Foundation
import XCTest
@testable import EmailGobblerCore

final class WorkflowTests: XCTestCase {
    private static let sheetA = SheetTarget(workbook: URL(fileURLWithPath: "/tmp/A.numbers"), sheetName: "Sheet A")
    private static let sheetB = SheetTarget(workbook: URL(fileURLWithPath: "/tmp/B.numbers"), sheetName: "Sheet B")

    private static func oneRow(_ text: String) -> SheetUpdatePlan {
        SheetUpdatePlan(placement: .insertBelow(row: 2), rows: [PlannedRow(values: [1: .text(text)], displays: [:])],
                        templateRequirements: [:])
    }
    private static var noRows: SheetUpdatePlan { SheetUpdatePlan(placement: .insertBelow(row: 2), rows: [], templateRequirements: [:]) }

    private struct FakeUseCase: MailToNumbersUseCase {
        var targets: [SheetTarget] = [WorkflowTests.sheetA, WorkflowTests.sheetB]
        var updates: [SheetTarget: SheetUpdatePlan] = [WorkflowTests.sheetA: WorkflowTests.oneRow("a"),
                                                       WorkflowTests.sheetB: WorkflowTests.oneRow("b")]
        var failPlan = false
        let mailQuery = MailQuery(subjectContains: "Synthetic", senderContains: nil)

        func summarize(html: String) throws -> [String] { ["summary of \(html)"] }

        func plan(html: String, sheets: [SheetTarget: SheetSnapshot]) throws -> UseCasePlan {
            struct PlanFailure: Error {}
            if failPlan { throw PlanFailure() }
            XCTAssertEqual(Set(sheets.keys), Set(targets))
            return UseCasePlan(targets: targets.map { TargetPlan(target: $0, update: updates[$0]!) }, notes: ["note"])
        }
    }

    private struct WriteFailure: Error, CustomStringConvertible {
        var description: String { "disk full" }
    }

    private let sheet = SheetSnapshot(rows: [[SheetCell(value: .text("Name"), formatted: "Name", format: .automatic)],
                                             [SheetCell(value: .text("row"), formatted: "row", format: .text)]])
    private var events: [String] = []

    private func actions(read: Bool = true, write: Bool = true, consume: Bool = true,
                         failWriteOn: SheetTarget? = nil) -> MessageActions {
        MessageActions(
            readSheet: read ? { [sheet] target in self.events.append("read \(target.sheetName)"); return sheet } : nil,
            write: write ? { plan, _ in
                self.events.append("write \(plan.target.sheetName)")
                if plan.target == failWriteOn { throw WriteFailure() }
            } : nil,
            consume: consume ? { self.events.append("consume") } : nil
        )
    }

    func testSummaryOnlyDoesNotTouchWorkbooksOrMail() throws {
        let report = try processMessage(html: "<html>", useCase: FakeUseCase(),
                                        actions: actions(read: false, write: false, consume: false))
        XCTAssertEqual(report, MessageReport(summary: ["summary of <html>"], notes: [], targets: [], consumed: false))
        XCTAssertEqual(events, [])
    }

    func testPreviewReadsEveryTargetButNeverWritesOrConsumes() throws {
        let report = try processMessage(html: "<html>", useCase: FakeUseCase(), actions: actions(write: false, consume: false))
        XCTAssertEqual(events, ["read Sheet A", "read Sheet B"])
        XCTAssertEqual(report.notes, ["note"])
        XCTAssertEqual(report.targets.map(\.status), [.previewed, .previewed])
        XCTAssertEqual(report.targets.map(\.plannedRows), [1, 1])
        XCTAssertEqual(report.targets.first?.preview, ["Plan: insert 1 row(s) below row 2", "  Row 3: Name: a"])
        XCTAssertFalse(report.consumed)
    }

    func testEveryTargetIsWrittenBeforeTheMessageIsConsumed() throws {
        let report = try processMessage(html: "<html>", useCase: FakeUseCase(), actions: actions())
        XCTAssertEqual(events, ["read Sheet A", "read Sheet B", "write Sheet A", "write Sheet B", "consume"])
        XCTAssertEqual(report.targets.map(\.status), [.written, .written])
        XCTAssertTrue(report.consumed)
    }

    func testTargetsWithNothingToWriteAreSkippedAndTheMessageIsStillConsumed() throws {
        var useCase = FakeUseCase()
        useCase.updates[Self.sheetA] = Self.noRows
        let report = try processMessage(html: "<html>", useCase: useCase, actions: actions())
        XCTAssertEqual(events, ["read Sheet A", "read Sheet B", "write Sheet B", "consume"])
        XCTAssertEqual(report.targets.map(\.status), [.nothingToWrite, .written])

        events = []
        useCase.updates[Self.sheetB] = Self.noRows
        let empty = try processMessage(html: "<html>", useCase: useCase, actions: actions())
        XCTAssertEqual(events, ["read Sheet A", "read Sheet B", "consume"])
        XCTAssertEqual(empty.targets.map(\.status), [.nothingToWrite, .nothingToWrite])
    }

    func testFailedSecondWriteReportsTheWrittenTargetAndNeverConsumes() {
        XCTAssertThrowsError(try processMessage(html: "<html>", useCase: FakeUseCase(),
                                                actions: actions(failWriteOn: Self.sheetB))) { error in
            XCTAssertEqual(error as? PartialWriteError,
                           PartialWriteError(written: [Self.sheetA], failed: Self.sheetB, reason: "disk full"))
        }
        XCTAssertEqual(events, ["read Sheet A", "read Sheet B", "write Sheet A", "write Sheet B"])
    }

    func testFormatProblemOnAnyTargetStopsBeforeTheFirstWrite() {
        var useCase = FakeUseCase()
        useCase.updates[Self.sheetB] = SheetUpdatePlan(placement: .insertBelow(row: 2),
                                                        rows: [PlannedRow(values: [1: .text("b")], displays: [:])],
                                                        templateRequirements: [1: .currency])
        XCTAssertThrowsError(try processMessage(html: "<html>", useCase: useCase, actions: actions())) { error in
            XCTAssertEqual(error as? SheetError, .templateNotFormatted(row: 2, column: 1))
        }
        XCTAssertEqual(events, ["read Sheet A", "read Sheet B"])
    }

    func testFailedPlanNeverWritesOrConsumes() {
        XCTAssertThrowsError(try processMessage(html: "<html>", useCase: FakeUseCase(failPlan: true), actions: actions()))
        XCTAssertEqual(events, ["read Sheet A", "read Sheet B"])
    }

    func testPlanForAnUndeclaredTargetIsRejected() {
        struct StrayUseCase: MailToNumbersUseCase {
            let targets = [WorkflowTests.sheetA]
            let mailQuery = MailQuery(subjectContains: "Synthetic", senderContains: nil)
            func summarize(html: String) throws -> [String] { [] }
            func plan(html: String, sheets: [SheetTarget: SheetSnapshot]) throws -> UseCasePlan {
                UseCasePlan(targets: [TargetPlan(target: WorkflowTests.sheetB, update: WorkflowTests.oneRow("b"))], notes: [])
            }
        }
        XCTAssertThrowsError(try processMessage(html: "<html>", useCase: StrayUseCase(), actions: actions())) { error in
            XCTAssertEqual(error as? WorkflowError, .undeclaredTarget)
        }
        XCTAssertEqual(events, ["read Sheet A"])
    }

    func testConsumeWithoutWriteOrWriteWithoutReadIsRejected() {
        XCTAssertThrowsError(try processMessage(html: "<html>", useCase: FakeUseCase(), actions: actions(write: false))) { error in
            XCTAssertEqual(error as? WorkflowError, .invalidActions)
        }
        XCTAssertThrowsError(try processMessage(html: "<html>", useCase: FakeUseCase(), actions: actions(read: false))) { error in
            XCTAssertEqual(error as? WorkflowError, .invalidActions)
        }
        XCTAssertEqual(events, [])
    }
}

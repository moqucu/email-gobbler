import Foundation
import XCTest
@testable import MailNumbersCore

final class WorkflowTests: XCTestCase {
    private struct FakeUseCase: MailToNumbersUseCase {
        var update: SheetUpdatePlan
        var failPlan = false
        let mailQuery = MailQuery(subjectContains: "Synthetic", senderContains: nil)
        func summarize(html: String) throws -> [String] { ["summary of \(html)"] }
        func plan(html: String, sheet: SheetSnapshot) throws -> UseCasePlan {
            struct PlanFailure: Error {}
            if failPlan { throw PlanFailure() }
            return UseCasePlan(update: update, notes: ["note"])
        }
    }

    private struct WriteFailure: Error {}

    private let sheet = SheetSnapshot(rows: [[SheetCell(value: .text("Date"), formatted: "Date", format: .automatic)],
                                             [SheetCell(value: .text("row"), formatted: "row", format: .text)]])
    private let oneRow = SheetUpdatePlan(placement: .insertBelow(row: 2), rows: [PlannedRow(values: [1: .text("x")], displays: [:])],
                                         templateRequirements: [:])
    private let noRows = SheetUpdatePlan(placement: .insertBelow(row: 2), rows: [], templateRequirements: [:])

    private var events: [String] = []

    private func actions(read: Bool = true, write: Bool = true, consume: Bool = true, failWrite: Bool = false) -> MessageActions {
        MessageActions(
            readSheet: read ? { [sheet] in self.events.append("read"); return sheet } : nil,
            write: write ? { _, _ in
                self.events.append("write")
                if failWrite { throw WriteFailure() }
            } : nil,
            consume: consume ? { self.events.append("consume") } : nil
        )
    }

    func testSummaryOnlyDoesNotTouchTheWorkbookOrMail() throws {
        var lines: [String] = []
        let outcome = try processMessage(html: "<html>", useCase: FakeUseCase(update: oneRow),
                                         actions: actions(read: false, write: false, consume: false)) { lines.append($0) }
        XCTAssertEqual(outcome, .summarized)
        XCTAssertEqual(events, [])
        XCTAssertEqual(lines.first, "summary of <html>")
    }

    func testPreviewReadsButNeverWritesOrConsumes() throws {
        var lines: [String] = []
        let outcome = try processMessage(html: "<html>", useCase: FakeUseCase(update: oneRow),
                                         actions: actions(write: false, consume: false)) { lines.append($0) }
        XCTAssertEqual(outcome, .previewed(rows: 1))
        XCTAssertEqual(events, ["read"])
        XCTAssertTrue(lines.contains("note"))
    }

    func testPreviewReportsMissingAnchorFormattingBeforeAnyWrite() {
        let needsDate = SheetUpdatePlan(placement: .insertBelow(row: 1), rows: [PlannedRow(values: [1: .text("x")], displays: [:])],
                                        templateRequirements: [1: .dateOnly(.monthDayFullYear)])
        XCTAssertThrowsError(try processMessage(html: "<html>", useCase: FakeUseCase(update: needsDate),
                                                actions: actions()) { _ in }) { error in
            XCTAssertEqual(error as? SheetError, .invalidPlacement)
        }
        XCTAssertEqual(events, ["read"])
    }

    func testWriteHappensBeforeConsume() throws {
        let outcome = try processMessage(html: "<html>", useCase: FakeUseCase(update: oneRow), actions: actions()) { _ in }
        XCTAssertEqual(outcome, .written(rows: 1))
        XCTAssertEqual(events, ["read", "write", "consume"])
    }

    func testEmptyPlanSkipsTheWriteButStillConsumes() throws {
        let outcome = try processMessage(html: "<html>", useCase: FakeUseCase(update: noRows), actions: actions()) { _ in }
        XCTAssertEqual(outcome, .nothingToWrite)
        XCTAssertEqual(events, ["read", "consume"])
    }

    func testFailedWriteOrPlanNeverConsumes() {
        XCTAssertThrowsError(try processMessage(html: "<html>", useCase: FakeUseCase(update: oneRow),
                                                actions: actions(failWrite: true)) { _ in })
        XCTAssertEqual(events, ["read", "write"])
        events = []
        XCTAssertThrowsError(try processMessage(html: "<html>", useCase: FakeUseCase(update: oneRow, failPlan: true),
                                                actions: actions()) { _ in })
        XCTAssertEqual(events, ["read"])
    }

    func testConsumeWithoutWriteOrWriteWithoutReadIsRejected() {
        XCTAssertThrowsError(try processMessage(html: "<html>", useCase: FakeUseCase(update: oneRow),
                                                actions: actions(write: false)) { _ in }) { error in
            XCTAssertEqual(error as? WorkflowError, .invalidActions)
        }
        XCTAssertThrowsError(try processMessage(html: "<html>", useCase: FakeUseCase(update: oneRow),
                                                actions: actions(read: false)) { _ in }) { error in
            XCTAssertEqual(error as? WorkflowError, .invalidActions)
        }
        XCTAssertEqual(events, [])
    }
}

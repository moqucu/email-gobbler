import Foundation
import XCTest
@testable import EmailGobblerService

final class MenuStatusTests: XCTestCase {
    private func time(_ date: Date) -> String { "T\(Int(date.timeIntervalSince1970))" }

    private func summary(_ results: [UseCaseRunResult]) -> RunSummary {
        RunSummary(startedAt: Date(timeIntervalSince1970: 100), finishedAt: Date(timeIntervalSince1970: 160), results: results)
    }

    private let dividendsOK = UseCaseRunResult(id: .etradeDividends, messagesFound: 3, messagesProcessed: 3, rowsWritten: 4, error: nil)
    private let gradesNone = UseCaseRunResult(id: .schoologyGrades, messagesFound: 0, messagesProcessed: 0, rowsWritten: 0, error: nil)
    private let dividendsStopped = UseCaseRunResult(id: .etradeDividends, messagesFound: 2, messagesProcessed: 1, rowsWritten: 1,
                                                    error: "Workbook changed since the preview; no write attempted")

    private func status(_ state: CoordinatorState, _ last: RunSummary? = nil, issues: [SettingsIssue] = [],
                        enabled: Bool = true) -> MenuStatus {
        menuStatus(status: CoordinatorStatus(state: state, lastSummary: last), settingsIssues: issues,
                   hasEnabledUseCases: enabled, formatTime: time)
    }

    func testNeverRunAndIdle() {
        XCTAssertEqual(status(.idle), MenuStatus(symbol: .idle, headline: "Waiting for the first run", details: [], pauseTitle: "Pause"))
    }

    func testSuccessfulRunSummarizesEachUseCase() {
        XCTAssertEqual(status(.idle, summary([gradesNone, dividendsOK])), MenuStatus(
            symbol: .idle, headline: "Up to date",
            details: ["Last run: T160", "Schoology grades: no new email", "E*TRADE dividends: 3 emails, 4 rows written"],
            pauseTitle: "Pause"))
    }

    func testSingularCounts() {
        let one = UseCaseRunResult(id: .etradeDividends, messagesFound: 1, messagesProcessed: 1, rowsWritten: 1, error: nil)
        XCTAssertEqual(status(.idle, summary([one])).details.last, "E*TRADE dividends: 1 email, 1 row written")
    }

    func testRunningKeepsTheLastRunDetails() {
        XCTAssertEqual(status(.running, summary([dividendsOK])), MenuStatus(
            symbol: .running, headline: "Checking mail…",
            details: ["Last run: T160", "E*TRADE dividends: 3 emails, 4 rows written"], pauseTitle: "Pause"))
    }

    func testStoppedRunNeedsAttention() {
        XCTAssertEqual(status(.idle, summary([gradesNone, dividendsStopped])), MenuStatus(
            symbol: .attention, headline: "Last run stopped",
            details: ["Last run: T160", "Schoology grades: no new email",
                      "E*TRADE dividends: stopped after 1 of 2 emails: Workbook changed since the preview; no write attempted"],
            pauseTitle: "Pause"))
    }

    func testPausedShowsResumeAndStillReportsTheLastRun() {
        XCTAssertEqual(status(.paused, summary([dividendsStopped])), MenuStatus(
            symbol: .paused, headline: "Paused",
            details: ["Last run: T160",
                      "E*TRADE dividends: stopped after 1 of 2 emails: Workbook changed since the preview; no write attempted"],
            pauseTitle: "Resume"))
    }

    func testUnconfiguredAndInvalidSettingsNeedAttention() {
        XCTAssertEqual(status(.idle, enabled: false), MenuStatus(
            symbol: .attention, headline: "Not set up",
            details: ["Open Settings… to choose workbooks"], pauseTitle: "Pause"))
        let issues = [SettingsIssue(field: "dividends.workbookPath", message: "Choose the dividend ledger workbook")]
        XCTAssertEqual(status(.idle, summary([dividendsOK]), issues: issues), MenuStatus(
            symbol: .attention, headline: "Settings need attention",
            details: ["Choose the dividend ledger workbook"], pauseTitle: "Pause"))
    }
}

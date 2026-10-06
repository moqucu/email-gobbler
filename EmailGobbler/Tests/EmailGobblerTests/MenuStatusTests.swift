import Foundation
import XCTest
@testable import EmailGobblerService

final class MenuStatusTests: XCTestCase {
    private func time(_ date: Date) -> String { "T\(Int(date.timeIntervalSince1970))" }

    private func summary(_ results: [UseCaseRunResult]) -> RunSummary {
        RunSummary(startedAt: Date(timeIntervalSince1970: 100), finishedAt: Date(timeIntervalSince1970: 160), results: results)
    }

    private let both: [UseCaseID] = [.schoologyGrades, .etradeDividends]
    private let history = ProcessingHistory(lastProcessed: ["etrade-dividends": Date(timeIntervalSince1970: 150)])
    private let gradesNone = UseCaseRunResult(id: .schoologyGrades, messagesFound: 0, messagesProcessed: 0, rowsWritten: 0, error: nil)
    private let dividendsOK = UseCaseRunResult(id: .etradeDividends, messagesFound: 3, messagesProcessed: 3, rowsWritten: 4,
                                               error: nil, lastProcessedAt: Date(timeIntervalSince1970: 150))
    private let dividendsStopped = UseCaseRunResult(id: .etradeDividends, messagesFound: 2, messagesProcessed: 1, rowsWritten: 1,
                                                    error: "Workbook changed since the preview; no write attempted")

    private func status(_ state: CoordinatorState, _ last: RunSummary? = nil, issues: [SettingsIssue] = [],
                        enabled: [UseCaseID]? = nil, history: ProcessingHistory? = nil) -> MenuStatus {
        menuStatus(status: CoordinatorStatus(state: state, lastSummary: last), settingsIssues: issues,
                   enabledUseCases: enabled ?? both, history: history ?? self.history, formatTime: time)
    }

    func testBeforeTheFirstRunTheRememberedHistoryIsShown() {
        XCTAssertEqual(status(.idle), MenuStatus(
            symbol: .idle, headline: "Waiting for the first run",
            details: ["Schoology grades: no email processed yet", "E*TRADE dividends: last email T150"],
            pauseTitle: "Pause"))
    }

    func testSuccessfulRunShowsWhenEachUseCaseLastProcessedAnEmail() {
        XCTAssertEqual(status(.idle, summary([gradesNone, dividendsOK])), MenuStatus(
            symbol: .idle, headline: "Up to date",
            details: ["Last run: T160", "Schoology grades: no email processed yet", "E*TRADE dividends: last email T150"],
            pauseTitle: "Pause"))
    }

    func testRunningKeepsTheDetails() {
        XCTAssertEqual(status(.running, summary([dividendsOK]), enabled: [.etradeDividends]), MenuStatus(
            symbol: .running, headline: "Checking mail…",
            details: ["Last run: T160", "E*TRADE dividends: last email T150"], pauseTitle: "Pause"))
    }

    func testStoppedRunShowsTheReasonInsteadOfTheLastEmail() {
        XCTAssertEqual(status(.idle, summary([gradesNone, dividendsStopped])), MenuStatus(
            symbol: .attention, headline: "Last run stopped",
            details: ["Last run: T160", "Schoology grades: no email processed yet",
                      "E*TRADE dividends: stopped after 1 of 2 emails: Workbook changed since the preview; no write attempted"],
            pauseTitle: "Pause"))
    }

    func testPausedShowsResumeAndTheDetails() {
        XCTAssertEqual(status(.paused, summary([dividendsOK]), enabled: [.etradeDividends]), MenuStatus(
            symbol: .paused, headline: "Paused", details: ["Last run: T160", "E*TRADE dividends: last email T150"],
            pauseTitle: "Resume"))
    }

    func testUnconfiguredAndInvalidSettingsNeedAttention() {
        XCTAssertEqual(status(.idle, enabled: []), MenuStatus(
            symbol: .attention, headline: "Not set up", details: ["Open Settings… to choose workbooks"], pauseTitle: "Pause"))
        let issues = [SettingsIssue(field: "dividends.workbookPath", message: "Choose the dividend ledger workbook")]
        XCTAssertEqual(status(.idle, summary([dividendsOK]), issues: issues), MenuStatus(
            symbol: .attention, headline: "Settings need attention",
            details: ["Choose the dividend ledger workbook"], pauseTitle: "Pause"))
    }

    // MARK: - History

    func testHistoryRecordsOnlyUseCasesThatProcessedAnEmail() {
        let earlier = ProcessingHistory(lastProcessed: ["schoology-grades": Date(timeIntervalSince1970: 10)])
        let updated = earlier.recording(summary([gradesNone, dividendsOK, dividendsStopped]))
        XCTAssertEqual(updated.lastProcessed(.schoologyGrades), Date(timeIntervalSince1970: 10))
        XCTAssertEqual(updated.lastProcessed(.etradeDividends), Date(timeIntervalSince1970: 150))
        XCTAssertNil(ProcessingHistory().lastProcessed(.etradeDividends))
    }

    func testHistoryStoreRoundTripsAndStartsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProcessingHistoryStore(directory: directory)
        XCTAssertEqual(store.load(), ProcessingHistory())
        try store.save(history)
        XCTAssertEqual(store.load(), history)
        XCTAssertEqual(ProcessingHistoryStore.standard.fileURL.lastPathComponent, "history.json")
    }
}

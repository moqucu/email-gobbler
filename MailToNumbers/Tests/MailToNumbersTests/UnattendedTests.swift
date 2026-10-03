import Foundation
import XCTest
@testable import MailNumbersCore
@testable import MailToNumbersService

final class UnattendedTests: XCTestCase {
    // MARK: - Foreground

    private let terminal: Int32 = 100
    private let numbers: Int32 = 200

    func testRunThatLaunchedNumbersHidesIt() {
        let before = ForegroundSnapshot(frontmostPID: terminal, numbersPID: nil, numbersHidden: false)
        let after = ForegroundSnapshot(frontmostPID: terminal, numbersPID: numbers, numbersHidden: false)
        XCTAssertEqual(foregroundActions(before: before, after: after), [.hideNumbers])
    }

    func testNumbersTakingFocusIsHiddenAndFocusReturns() {
        let before = ForegroundSnapshot(frontmostPID: terminal, numbersPID: nil, numbersHidden: false)
        let after = ForegroundSnapshot(frontmostPID: numbers, numbersPID: numbers, numbersHidden: false)
        XCTAssertEqual(foregroundActions(before: before, after: after), [.hideNumbers, .activate(pid: terminal)])
    }

    func testVisibleNumbersTheUserWasUsingIsLeftAlone() {
        let using = ForegroundSnapshot(frontmostPID: numbers, numbersPID: numbers, numbersHidden: false)
        XCTAssertEqual(foregroundActions(before: using, after: using), [])
        let background = ForegroundSnapshot(frontmostPID: terminal, numbersPID: numbers, numbersHidden: false)
        XCTAssertEqual(foregroundActions(before: background, after: background), [])
    }

    func testRunningNumbersThatTookFocusGivesItBackWithoutHiding() {
        let before = ForegroundSnapshot(frontmostPID: terminal, numbersPID: numbers, numbersHidden: false)
        let after = ForegroundSnapshot(frontmostPID: numbers, numbersPID: numbers, numbersHidden: false)
        XCTAssertEqual(foregroundActions(before: before, after: after), [.activate(pid: terminal)])
    }

    func testHiddenNumbersIsHiddenAgain() {
        let before = ForegroundSnapshot(frontmostPID: terminal, numbersPID: numbers, numbersHidden: true)
        let after = ForegroundSnapshot(frontmostPID: terminal, numbersPID: numbers, numbersHidden: false)
        XCTAssertEqual(foregroundActions(before: before, after: after), [.hideNumbers])
    }

    // MARK: - Open workbooks

    func testOpenWorkbookIsRecognizedByPathIgnoringCaseAndTrailingSlash() {
        let ledger = URL(fileURLWithPath: "/Users/someone/Library/Mobile Documents/com~apple~Numbers/Documents/Ledger.numbers")
        XCTAssertTrue(isWorkbookOpen(ledger, openPaths: ["/tmp/Other.numbers", ledger.path]))
        XCTAssertTrue(isWorkbookOpen(ledger, openPaths: [ledger.path.lowercased() + "/"]))
        XCTAssertFalse(isWorkbookOpen(ledger, openPaths: ["/tmp/Ledger.numbers"]))
        XCTAssertFalse(isWorkbookOpen(ledger, openPaths: []))
    }

    func testOpenWorkbookErrorAsksToCloseIt() {
        XCTAssertEqual(AutomationError.workbookOpen("Ledger.numbers").description,
                       "Close Ledger.numbers in Numbers; it will be updated on the next run")
    }

    // MARK: - iCloud availability

    func testWorkbookAvailability() {
        XCTAssertEqual(workbookAvailability(exists: true, placeholderExists: false, downloadStatus: nil), .available)
        XCTAssertEqual(workbookAvailability(exists: true, placeholderExists: false,
                                            downloadStatus: NSMetadataUbiquitousItemDownloadingStatusCurrent), .available)
        XCTAssertEqual(workbookAvailability(exists: true, placeholderExists: false,
                                            downloadStatus: NSMetadataUbiquitousItemDownloadingStatusDownloaded), .available)
        XCTAssertEqual(workbookAvailability(exists: true, placeholderExists: false,
                                            downloadStatus: NSMetadataUbiquitousItemDownloadingStatusNotDownloaded), .downloading)
        XCTAssertEqual(workbookAvailability(exists: false, placeholderExists: true, downloadStatus: nil), .downloading)
        XCTAssertEqual(workbookAvailability(exists: false, placeholderExists: false, downloadStatus: nil), .missing)
    }

    // MARK: - Failure notifications

    private func summary(_ results: [UseCaseRunResult]) -> RunSummary {
        RunSummary(startedAt: Date(timeIntervalSince1970: 0), finishedAt: Date(timeIntervalSince1970: 1), results: results)
    }

    private func result(_ id: UseCaseID, error: String?) -> UseCaseRunResult {
        UseCaseRunResult(id: id, messagesFound: 1, messagesProcessed: 0, rowsWritten: 0, error: error)
    }

    func testNewFailureNotifiesWithoutErrorDetails() {
        let notice = failureNotice(previous: nil, current: summary([result(.schoologyGrades, error: nil),
                                                                    result(.etradeDividends, error: "Alert amount is malformed: $3.x9")]))
        XCTAssertEqual(notice, FailureNotice(title: "Email Gobbler needs attention",
                                             body: "E*TRADE dividends stopped. Open the Email Gobbler menu for details."))
    }

    func testRepeatedSameFailureDoesNotNotifyAgainButAChangedOneDoes() {
        let failing = summary([result(.etradeDividends, error: "Close Ledger.numbers in Numbers; it will be updated on the next run")])
        XCTAssertNil(failureNotice(previous: failing, current: failing))
        let both = summary([result(.schoologyGrades, error: "Workbook changed since the preview; no write attempted"),
                            result(.etradeDividends, error: "Close Ledger.numbers in Numbers; it will be updated on the next run")])
        XCTAssertEqual(failureNotice(previous: failing, current: both)?.body,
                       "Schoology grades stopped. Open the Email Gobbler menu for details.")
    }

    func testSuccessfulRunDoesNotNotify() {
        XCTAssertNil(failureNotice(previous: summary([result(.etradeDividends, error: "x")]),
                                   current: summary([result(.etradeDividends, error: nil)])))
    }

    func testSeveralNewFailuresAreNamedTogether() {
        let notice = failureNotice(previous: nil, current: summary([result(.schoologyGrades, error: "a"),
                                                                    result(.etradeDividends, error: "b")]))
        XCTAssertEqual(notice?.body, "Schoology grades and E*TRADE dividends stopped. Open the Email Gobbler menu for details.")
    }
}

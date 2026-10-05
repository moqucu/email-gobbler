import Foundation
import XCTest
import EmailGobblerCore
import EtradeDividends
import SchoologyGrades
@testable import EmailGobblerService

final class SetupChecksTests: XCTestCase {
    private func text(_ s: String) -> SheetCell { SheetCell(value: .text(s), formatted: s, format: .automatic) }
    private let blank = SheetCell(value: .empty, formatted: nil, format: .automatic)
    private func date(_ shown: String, _ format: NumbersCellFormat = .dateAndTime) -> SheetCell {
        SheetCell(value: .date(try! CalendarDate(year: 2026, month: 9, day: 21)), formatted: shown, format: format)
    }

    // MARK: - Dividend ledger

    private func ledgerRow(date dateCell: SheetCell? = nil, amount: SheetCell? = nil) -> [SheetCell] {
        [text("E*Trade Financial"), text("XXXX-0042"), text("Dividend or Interest Paid"),
         dateCell ?? date("9/21/2026"), text("FUND (FUND)"),
         amount ?? SheetCell(value: .number(3), formatted: "$3.00", format: .currency)]
    }

    private func ledger(_ rows: [[SheetCell]], headers: [String] = DividendLedger.headers) -> SheetSnapshot {
        SheetSnapshot(rows: [headers.map(text)] + rows)
    }

    func testFormattedLedgerHasNoProblems() {
        XCTAssertEqual(checkDividendLedger(ledger([ledgerRow(), ledgerRow(), Array(repeating: blank, count: 6)])), [])
    }

    func testLedgerProblemsSayWhatToFix() {
        XCTAssertEqual(checkDividendLedger(ledger([], headers: ["Financial Institution", "Type", "Security"])),
                       ["Missing columns: Account, Date, Amount Credited"])
        XCTAssertEqual(checkDividendLedger(ledger([Array(repeating: blank, count: 6)])),
                       ["Enter the first payment by hand so new rows can copy its formatting"])
        XCTAssertEqual(checkDividendLedger(ledger([ledgerRow(), ledgerRow(date: date("9/21/26 12:00 AM", .automatic),
                                                                            amount: SheetCell(value: .number(3), formatted: "3", format: .automatic))])),
                       ["Format the Date column like 9/21/2026 (row 3)", "Format Amount Credited as Currency (row 3)"])
    }

    // MARK: - Grades sheet

    private func gradesRow(date dateCell: SheetCell? = nil, percent: SheetCell? = nil) -> [SheetCell] {
        [dateCell ?? date("9/21/26"), percent ?? SheetCell(value: .number(0.88), formatted: "88%", format: .percent), text("B+"),
         SheetCell(value: .empty, formatted: nil, format: .percent), blank]
    }

    private func grades(_ rows: [[SheetCell]], headers: [String] = ["Date", "Algebra 2", "", "AP Biology", ""]) -> SheetSnapshot {
        SheetSnapshot(rows: [headers.map(text)] + rows)
    }

    func testFormattedGradesSheetHasNoProblems() {
        XCTAssertEqual(checkGradesSheet(grades([gradesRow(), gradesRow()])), [])
    }

    func testGradesProblemsSayWhatToFix() {
        XCTAssertEqual(checkGradesSheet(grades([gradesRow()], headers: ["Week", "Algebra 2", ""])),
                       ["Start with a Date column, then each course name followed by a blank letter column"])
        XCTAssertEqual(checkGradesSheet(grades([Array(repeating: blank, count: 5)])),
                       ["Enter the first week by hand so new rows can copy its formatting"])
        XCTAssertEqual(checkGradesSheet(grades([gradesRow(date: date("9/21/2026"),
                                                          percent: SheetCell(value: .number(0.8794), formatted: "87.94%", format: .percent))])),
                       ["Format the Date column like 9/21/26 (row 2)",
                        "Format Algebra 2 as Percentage with 0 decimal places (row 2)"])
    }

    // MARK: - Preflight

    private func settings() -> AppSettings {
        AppSettings(intervalMinutes: 30, backupRetention: 30,
                    grades: GradesSettings(enabled: true, routes: [
                        StudentRouteSettings(studentLabel: "Student Alpha", workbookPath: "/tmp/Grades.numbers", sheetName: "Alpha"),
                    ]),
                    dividends: DividendsSettings(enabled: true, workbookPath: "/tmp/Ledger.numbers", sheetName: "Sheet 1"))
    }

    func testPreflightReadsEachEnabledSheetAndNamesTheField() {
        var read: [String] = []
        let issues = preflightIssues(settings()) { target in
            read.append(target.sheetName)
            return target.sheetName == "Alpha" ? self.grades([self.gradesRow()]) : self.ledger([])
        }
        XCTAssertEqual(read, ["Alpha", "Sheet 1"])
        XCTAssertEqual(issues, [SettingsIssue(field: "dividends.sheetName",
                                              message: "Sheet 1: Enter the first payment by hand so new rows can copy its formatting")])
    }

    func testPreflightReportsUnreadableSheetsAndSkipsDisabledOrInvalidSettings() {
        struct NoSheet: Error, CustomStringConvertible { var description: String { "Can’t get sheet \"Alpha\"" } }
        var settings = settings()
        settings.dividends.enabled = false
        XCTAssertEqual(preflightIssues(settings) { _ in throw NoSheet() },
                       [SettingsIssue(field: "grades.routes[0].sheetName", message: "Alpha: Can’t get sheet \"Alpha\"")])
        settings.grades.routes[0].workbookPath = ""
        XCTAssertEqual(preflightIssues(settings) { _ in XCTFail("should not read"); throw NoSheet() }, [])
    }

    // MARK: - Sheet names and login item

    func testSheetNamesAreReadOnePerLine() {
        XCTAssertEqual(parseSheetNames("Sheet 1\nStudent 2026/27\n\n"), ["Sheet 1", "Student 2026/27"])
        XCTAssertEqual(parseSheetNames(""), [])
    }

    func testLoginItemExplanations() {
        XCTAssertEqual(LoginItemState.enabled.explanation, "Starts when you log in.")
        XCTAssertEqual(LoginItemState.requiresApproval.explanation,
                       "Allow EmailGobbler in System Settings › General › Login Items.")
        XCTAssertEqual(LoginItemState.notRegistered.explanation, "Does not start at login.")
        XCTAssertEqual(LoginItemState.notFound.explanation,
                       "Install the app in /Applications to start it at login.")
    }
}

import Foundation
import XCTest
import MailNumbersCore
@testable import EtradeDividends

final class DividendLedgerPlannerTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> CalendarDate { try! CalendarDate(year: y, month: m, day: d) }
    private func dec(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }
    private func text(_ s: String) -> SheetCell { SheetCell(value: .text(s), formatted: s, format: .text) }
    private let blank = SheetCell(value: .empty, formatted: nil, format: .automatic)

    private func header(_ names: [String] = DividendLedger.headers) -> [SheetCell] {
        names.map { SheetCell(value: .text($0), formatted: $0, format: .automatic) }
    }

    private func ledgerRow(_ account: String, _ day: CalendarDate, _ security: String, _ amount: String) -> [SheetCell] {
        [text("E*Trade Financial"), text(account), text("Dividend or Interest Paid"),
         SheetCell(value: .date(day), formatted: "\(day.month)/\(day.day)/\(day.year)", format: .dateAndTime),
         text(security), SheetCell(value: .number(dec(amount)), formatted: "$\(amount)", format: .currency)]
    }

    private func sheet(_ rows: [[SheetCell]]) -> SheetSnapshot { SheetSnapshot(rows: [header()] + rows) }

    private func alert(_ payments: [(String, String)], account: String = "XXXXX-0042", on day: CalendarDate? = nil) -> DividendAlert {
        DividendAlert(accountMask: account, paymentDate: day ?? date(2026, 3, 16),
                      payments: payments.map { DividendPayment(security: $0.0, amount: dec($0.1)) })
    }

    private func expectedRow(_ security: String, _ amount: String, account: String = "XXXX-0042", on day: CalendarDate? = nil) -> PlannedRow {
        let day = day ?? date(2026, 3, 16)
        return PlannedRow(
            values: [1: .text("E*Trade Financial"), 2: .text(account), 3: .text("Dividend or Interest Paid"),
                     4: .date(day), 5: .text(security), 6: .number(dec(amount))],
            displays: [4: .exact("\(day.month)/\(day.day)/\(day.year)"), 6: .currency(of: dec(amount))]
        )
    }

    private let requirements: [Int: FormatRequirement] = [4: .dateOnly(.monthDayFullYear), 6: .currency]

    private func assertLedgerError<T>(_ expected: DividendLedgerError, _ expression: @autoclosure () throws -> T,
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? DividendLedgerError, expected, file: file, line: line)
        }
    }

    func testAccountMaskIsNormalizedToFourMaskedDigits() throws {
        XCTAssertEqual(try normalizedAccount("XXXXX-0042"), "XXXX-0042")
        XCTAssertEqual(try normalizedAccount("XXXX-1234"), "XXXX-1234")
        XCTAssertEqual(try normalizedAccount(" XXXXXXX-9876 "), "XXXX-9876")
        assertLedgerError(.unsupportedAccount("XXXXX-42"), try normalizedAccount("XXXXX-42"))
        assertLedgerError(.unsupportedAccount("Brokerage"), try normalizedAccount("Brokerage"))
    }

    func testNewPaymentIsAppendedBelowTheLastRowRegardlessOfDateOrder() throws {
        let snapshot = sheet([
            ledgerRow("XXXX-0042", date(2026, 3, 20), "LATER FUND (LATR)", "2.00"),
            ledgerRow("XXXX-0042", date(2026, 3, 2), "EARLIER FUND (ERLR)", "1.00"),
        ])
        let result = try planDividendLedgerUpdate(alert: alert([("EXAMPLE FUND (EXFI)", "12.34")]), sheet: snapshot)
        XCTAssertEqual(result.update, SheetUpdatePlan(placement: .insertBelow(row: 3),
                                                      rows: [expectedRow("EXAMPLE FUND (EXFI)", "12.34")],
                                                      templateRequirements: requirements))
        XCTAssertEqual(result.alreadyRecorded, [])
    }

    func testTrailingEmptyRowsAreSkippedWhenChoosingTheAnchor() throws {
        let snapshot = sheet([ledgerRow("XXXX-0042", date(2026, 3, 2), "EARLIER FUND (ERLR)", "1.00"),
                              Array(repeating: blank, count: 6), Array(repeating: blank, count: 6)])
        let result = try planDividendLedgerUpdate(alert: alert([("EXAMPLE FUND (EXFI)", "12.34")]), sheet: snapshot)
        XCTAssertEqual(result.update.placement, .insertBelow(row: 2))
    }

    func testIdenticalRecordedPaymentIsSkipped() throws {
        let snapshot = sheet([ledgerRow("XXXX-0042", date(2026, 3, 16), "EXAMPLE  FUND (EXFI)", "12.34")])
        let result = try planDividendLedgerUpdate(alert: alert([("EXAMPLE FUND (EXFI)", "12.34")]), sheet: snapshot)
        XCTAssertTrue(result.update.isEmpty)
        XCTAssertEqual(result.alreadyRecorded, [DividendPayment(security: "EXAMPLE FUND (EXFI)", amount: dec("12.34"))])
    }

    func testPaymentDifferingInAnyFieldIsNotADuplicate() throws {
        let snapshot = sheet([
            ledgerRow("XXXX-0042", date(2026, 3, 16), "EXAMPLE FUND (EXFI)", "12.35"),
            ledgerRow("XXXX-0043", date(2026, 3, 16), "EXAMPLE FUND (EXFI)", "12.34"),
            ledgerRow("XXXX-0042", date(2026, 3, 17), "EXAMPLE FUND (EXFI)", "12.34"),
            ledgerRow("XXXX-0042", date(2026, 3, 16), "OTHER FUND (OTHR)", "12.34"),
        ])
        let result = try planDividendLedgerUpdate(alert: alert([("EXAMPLE FUND (EXFI)", "12.34")]), sheet: snapshot)
        XCTAssertEqual(result.update.rows, [expectedRow("EXAMPLE FUND (EXFI)", "12.34")])
        XCTAssertEqual(result.update.placement, .insertBelow(row: 5))
    }

    func testOnlyUnrecordedPaymentsOfAnAlertAreAppendedInOrder() throws {
        let snapshot = sheet([ledgerRow("XXXX-0042", date(2026, 3, 16), "SECOND FUND (SCND)", "2.00")])
        let result = try planDividendLedgerUpdate(
            alert: alert([("FIRST FUND (FRST)", "1.00"), ("SECOND FUND (SCND)", "2.00"), ("THIRD FUND (THRD)", "3.00")]),
            sheet: snapshot)
        XCTAssertEqual(result.update.rows, [expectedRow("FIRST FUND (FRST)", "1.00"), expectedRow("THIRD FUND (THRD)", "3.00")])
        XCTAssertEqual(result.alreadyRecorded, [DividendPayment(security: "SECOND FUND (SCND)", amount: dec("2.00"))])
    }

    func testColumnsAreFoundByHeaderName() throws {
        let names = ["Date", "Security", "Amount Credited", "Account", "Type", "Financial Institution"]
        let row = ledgerRow("XXXX-0042", date(2026, 3, 2), "EARLIER FUND (ERLR)", "1.00")
        let snapshot = SheetSnapshot(rows: [header(names), [row[3], row[4], row[5], row[1], row[2], row[0]]])
        let result = try planDividendLedgerUpdate(alert: alert([("EXAMPLE FUND (EXFI)", "12.34")]), sheet: snapshot)
        XCTAssertEqual(result.update.rows.first?.values[1], .date(date(2026, 3, 16)))
        XCTAssertEqual(result.update.rows.first?.values[3], .number(dec("12.34")))
        XCTAssertEqual(result.update.rows.first?.values[6], .text("E*Trade Financial"))
        XCTAssertEqual(result.update.templateRequirements, [1: .dateOnly(.monthDayFullYear), 3: .currency])
    }

    func testUnexpectedHeadersOrEmptyLedgerAreRejected() {
        let missing = SheetSnapshot(rows: [header(["Financial Institution", "Account", "Type", "Date", "Security"])])
        assertLedgerError(.unexpectedHeaders, try planDividendLedgerUpdate(alert: alert([("A (A)", "1.00")]), sheet: missing))
        let duplicated = SheetSnapshot(rows: [header(DividendLedger.headers + ["Date"])])
        assertLedgerError(.unexpectedHeaders, try planDividendLedgerUpdate(alert: alert([("A (A)", "1.00")]), sheet: duplicated))
        assertLedgerError(.noTemplateRow, try planDividendLedgerUpdate(alert: alert([("A (A)", "1.00")]), sheet: sheet([])))
        assertLedgerError(.unsupportedAccount("Brokerage"),
                          try planDividendLedgerUpdate(alert: alert([("A (A)", "1.00")], account: "Brokerage"),
                                                       sheet: sheet([ledgerRow("XXXX-0042", date(2026, 3, 2), "A (A)", "1.00")])))
    }
}

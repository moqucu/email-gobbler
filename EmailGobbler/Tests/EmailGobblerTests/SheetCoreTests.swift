import Foundation
import XCTest
@testable import EmailGobblerCore

final class SheetCoreTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> CalendarDate { try! CalendarDate(year: y, month: m, day: d) }
    private func dec(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    private func cell(_ value: SheetValue, _ formatted: String? = nil, _ format: NumbersCellFormat = .automatic) -> SheetCell {
        SheetCell(value: value, formatted: formatted, format: format)
    }

    private func text(_ s: String) -> SheetCell { cell(.text(s), s, .text) }
    private let empty = SheetCell(value: .empty, formatted: nil, format: .automatic)

    /// Header plus two ledger rows in the shape of the dividends workbook.
    private func ledger() -> SheetSnapshot {
        SheetSnapshot(rows: [
            [text("Date"), text("Security"), text("Amount")],
            [cell(.date(date(2026, 9, 3)), "9/3/2026", .dateAndTime), text("ALPHA FUND (ALFA)"), cell(.number(dec("7.36")), "$7.36", .currency)],
            [cell(.date(date(2026, 9, 24)), "9/24/2026", .dateAndTime), text("BETA FUND (BETA)"), cell(.number(dec("5.24")), "$5.24", .currency)],
        ])
    }

    private func newPayment(_ day: Int, _ security: String, _ amount: String) -> PlannedRow {
        PlannedRow(
            values: [1: .date(date(2026, 9, day)), 2: .text(security), 3: .number(dec(amount))],
            displays: [1: .exact("9/\(day)/2026"), 3: .exact(currencyDisplay(dec(amount)))]
        )
    }

    private func assertSheetError<T>(_ expected: SheetError, _ expression: @autoclosure () throws -> T,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? SheetError, expected, file: file, line: line)
        }
    }

    // MARK: - Cell formats and displays

    func testFormatNamesFromNumbers() {
        XCTAssertEqual(NumbersCellFormat(appleScriptName: "automatic"), .automatic)
        XCTAssertEqual(NumbersCellFormat(appleScriptName: "date and time"), .dateAndTime)
        XCTAssertEqual(NumbersCellFormat(appleScriptName: "percent"), .percent)
        XCTAssertEqual(NumbersCellFormat(appleScriptName: "currency"), .currency)
        XCTAssertEqual(NumbersCellFormat(appleScriptName: "text"), .text)
        XCTAssertEqual(NumbersCellFormat(appleScriptName: "number"), .other("number"))
    }

    func testDateDisplayStyles() {
        XCTAssertEqual(DateDisplayStyle.monthDayShortYear.display(date(2026, 9, 21)), "9/21/26")
        XCTAssertEqual(DateDisplayStyle.monthDayShortYear.display(date(2005, 1, 2)), "1/2/05")
        XCTAssertEqual(DateDisplayStyle.monthDayFullYear.display(date(2026, 9, 24)), "9/24/2026")
        XCTAssertEqual(DateDisplayStyle.monthDayFullYear.display(date(2017, 12, 31)), "12/31/2017")
    }

    func testCurrencyDisplayUsesDollarsCentsAndThousands() {
        XCTAssertEqual(currencyDisplay(dec("3.39")), "$3.39")
        XCTAssertEqual(currencyDisplay(dec("3.4")), "$3.40")
        XCTAssertEqual(currencyDisplay(dec("12")), "$12.00")
        XCTAssertEqual(currencyDisplay(dec("1234.5")), "$1,234.50")
    }

    func testDisplayExpectations() {
        XCTAssertTrue(DisplayExpectation.exact("$3.39").matches("$3.39"))
        XCTAssertFalse(DisplayExpectation.exact("$3.39").matches("3.39"))
        XCTAssertTrue(DisplayExpectation.wholePercent(of: dec("0.8794")).matches("88%"))
        XCTAssertTrue(DisplayExpectation.wholePercent(of: dec("0.875")).matches("88%"))
        XCTAssertFalse(DisplayExpectation.wholePercent(of: dec("0.8794")).matches("87.94%"))
        XCTAssertFalse(DisplayExpectation.wholePercent(of: dec("0.8794")).matches("86%"))
        XCTAssertFalse(DisplayExpectation.wholePercent(of: dec("0.8794")).matches(nil))
    }

    func testCurrencyExpectationAcceptsCentsWithOrWithoutGrouping() {
        XCTAssertTrue(DisplayExpectation.currency(of: dec("3.39")).matches("$3.39"))
        XCTAssertTrue(DisplayExpectation.currency(of: dec("1234.5")).matches("$1,234.50"))
        XCTAssertTrue(DisplayExpectation.currency(of: dec("1234.5")).matches("$1234.50"))
        XCTAssertFalse(DisplayExpectation.currency(of: dec("3.39")).matches("3.39"))
        XCTAssertFalse(DisplayExpectation.currency(of: dec("3.39")).matches("$3.40"))
        XCTAssertFalse(DisplayExpectation.currency(of: dec("3.4")).matches("$3.4"))
    }

    // MARK: - Applying a plan to a snapshot

    func testAppendingRowsBelowTheLastRowKeepsExistingRowsAndOrder() throws {
        let plan = SheetUpdatePlan(placement: .insertBelow(row: 3), rows: [
            newPayment(28, "GAMMA FUND (GAMA)", "3.39"), newPayment(28, "DELTA FUND (DLTA)", "1.20"),
        ], templateRequirements: [:])
        let result = try plan.applied(to: ledger())
        XCTAssertEqual(result.rowCount, 5)
        XCTAssertEqual(result.rows[1].map(\.value), ledger().rows[1].map(\.value))
        XCTAssertEqual(result.rows[2].map(\.value), ledger().rows[2].map(\.value))
        XCTAssertEqual(result.rows[3].map(\.value), [.date(date(2026, 9, 28)), .text("GAMMA FUND (GAMA)"), .number(dec("3.39"))])
        XCTAssertEqual(result.rows[4].map(\.value), [.date(date(2026, 9, 28)), .text("DELTA FUND (DLTA)"), .number(dec("1.20"))])
    }

    func testInsertingAboveShiftsLaterRowsAndLeavesUnplannedColumnsEmpty() throws {
        let plan = SheetUpdatePlan(placement: .insertAbove(row: 2), rows: [
            PlannedRow(values: [1: .date(date(2026, 8, 1))], displays: [:]),
        ], templateRequirements: [:])
        let result = try plan.applied(to: ledger())
        XCTAssertEqual(result.rowCount, 4)
        XCTAssertEqual(result.rows[1].map(\.value), [.date(date(2026, 8, 1)), .empty, .empty])
        XCTAssertEqual(result.rows[2].map(\.value), ledger().rows[1].map(\.value))
    }

    func testReplacingKeepsUnplannedColumns() throws {
        let plan = SheetUpdatePlan(placement: .replace(row: 2), rows: [
            PlannedRow(values: [3: .number(dec("8"))], displays: [:]),
        ], templateRequirements: [:])
        let result = try plan.applied(to: ledger())
        XCTAssertEqual(result.rowCount, 3)
        XCTAssertEqual(result.rows[1].map(\.value), [.date(date(2026, 9, 3)), .text("ALPHA FUND (ALFA)"), .number(dec("8"))])
    }

    func testInvalidPlacementsAreRejected() {
        let one = [PlannedRow(values: [1: .text("x")], displays: [:])]
        assertSheetError(.invalidPlacement, try SheetUpdatePlan(placement: .replace(row: 1), rows: one, templateRequirements: [:]).applied(to: ledger()))
        assertSheetError(.invalidPlacement, try SheetUpdatePlan(placement: .insertBelow(row: 4), rows: one, templateRequirements: [:]).applied(to: ledger()))
        assertSheetError(.invalidPlacement, try SheetUpdatePlan(placement: .replace(row: 2), rows: one + one, templateRequirements: [:]).applied(to: ledger()))
        assertSheetError(.invalidPlacement, try SheetUpdatePlan(placement: .replace(row: 2), rows: [PlannedRow(values: [4: .text("x")], displays: [:])], templateRequirements: [:]).applied(to: ledger()))
    }

    func testEmptyPlanChangesNothing() throws {
        let plan = SheetUpdatePlan(placement: .insertBelow(row: 3), rows: [], templateRequirements: [:])
        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(try plan.applied(to: ledger()), ledger())
    }

    // MARK: - Formatting inherited from the anchor row

    func testTemplateRowIsTheAnchorRow() {
        XCTAssertEqual(RowPlacement.replace(row: 5).anchorRow, 5)
        XCTAssertEqual(RowPlacement.insertAbove(row: 2).anchorRow, 2)
        XCTAssertEqual(RowPlacement.insertBelow(row: 614).anchorRow, 614)
    }

    func testFormattedTemplateIsAccepted() throws {
        let plan = SheetUpdatePlan(placement: .insertBelow(row: 3), rows: [newPayment(28, "GAMMA FUND (GAMA)", "3.39")],
                                   templateRequirements: [1: .dateOnly(.monthDayFullYear), 3: .currency])
        XCTAssertNoThrow(try plan.validateTemplate(in: ledger()))
    }

    func testTemplateWithTimestampOrWrongStyleIsRejected() {
        var rows = ledger().rows
        rows[2][0] = cell(.date(date(2026, 9, 24)), "9/24/26 12:00 AM", .automatic)
        let plan = SheetUpdatePlan(placement: .insertBelow(row: 3), rows: [newPayment(28, "G", "1")],
                                   templateRequirements: [1: .dateOnly(.monthDayFullYear)])
        assertSheetError(.templateNotFormatted(row: 3, column: 1), try plan.validateTemplate(in: SheetSnapshot(rows: rows)))

        rows[2][0] = cell(.date(date(2026, 9, 24)), "9/24/26", .dateAndTime)
        assertSheetError(.templateNotFormatted(row: 3, column: 1), try plan.validateTemplate(in: SheetSnapshot(rows: rows)))
    }

    func testTemplateCurrencyAndPercentRequirements() {
        var rows = ledger().rows
        rows[2][2] = cell(.number(dec("5.24")), "5.24", .automatic)
        let currencyPlan = SheetUpdatePlan(placement: .insertBelow(row: 3), rows: [newPayment(28, "G", "1")],
                                           templateRequirements: [3: .currency])
        assertSheetError(.templateNotFormatted(row: 3, column: 3), try currencyPlan.validateTemplate(in: SheetSnapshot(rows: rows)))

        rows[2][2] = cell(.number(dec("0.8794")), "87.94%", .percent)
        let percentPlan = SheetUpdatePlan(placement: .insertBelow(row: 3), rows: [newPayment(28, "G", "1")],
                                          templateRequirements: [3: .wholePercent])
        assertSheetError(.templateNotFormatted(row: 3, column: 3), try percentPlan.validateTemplate(in: SheetSnapshot(rows: rows)))
        rows[2][2] = cell(.empty, nil, .percent)
        XCTAssertNoThrow(try percentPlan.validateTemplate(in: SheetSnapshot(rows: rows)))
    }

    // MARK: - Verifying the saved table

    func testSavedTableMatchingValuesAndDisplaysIsAccepted() throws {
        let plan = SheetUpdatePlan(placement: .insertBelow(row: 3), rows: [newPayment(28, "GAMMA FUND (GAMA)", "3.39")],
                                   templateRequirements: [:])
        var rows = ledger().rows
        rows.append([cell(.date(date(2026, 9, 28)), "9/28/2026", .dateAndTime), text("GAMMA FUND (GAMA)"), cell(.number(dec("3.39")), "$3.39", .currency)])
        XCTAssertNoThrow(try plan.verify(saved: SheetSnapshot(rows: rows), original: ledger()))
    }

    func testSavedTableWithChangedExistingRowIsRejected() {
        let plan = SheetUpdatePlan(placement: .insertBelow(row: 3), rows: [newPayment(28, "GAMMA FUND (GAMA)", "3.39")],
                                   templateRequirements: [:])
        var rows = ledger().rows
        rows[1][2] = cell(.number(dec("7.37")), "$7.37", .currency)
        rows.append([cell(.date(date(2026, 9, 28)), "9/28/2026", .dateAndTime), text("GAMMA FUND (GAMA)"), cell(.number(dec("3.39")), "$3.39", .currency)])
        assertSheetError(.valueMismatch(row: 2, column: 3), try plan.verify(saved: SheetSnapshot(rows: rows), original: ledger()))
    }

    func testSavedTableWithWrongDisplayOrRowCountIsRejected() {
        let plan = SheetUpdatePlan(placement: .insertBelow(row: 3), rows: [newPayment(28, "GAMMA FUND (GAMA)", "3.39")],
                                   templateRequirements: [:])
        var rows = ledger().rows
        rows.append([cell(.date(date(2026, 9, 28)), "9/28/26 12:00 AM", .automatic), text("GAMMA FUND (GAMA)"), cell(.number(dec("3.39")), "$3.39", .currency)])
        assertSheetError(.displayMismatch(row: 4, column: 1, actual: "9/28/26 12:00 AM"),
                         try plan.verify(saved: SheetSnapshot(rows: rows), original: ledger()))
        assertSheetError(.rowCountMismatch(expected: 4, actual: 3), try plan.verify(saved: ledger(), original: ledger()))
    }

    func testNumbersCompareByValueNotText() throws {
        let plan = SheetUpdatePlan(placement: .replace(row: 2), rows: [PlannedRow(values: [3: .number(dec("0.69"))], displays: [:])],
                                   templateRequirements: [:])
        var rows = ledger().rows
        rows[1][2] = cell(.number(dec("0.6900000000001")), "$0.69", .currency)
        XCTAssertNoThrow(try plan.verify(saved: SheetSnapshot(rows: rows), original: ledger()))
    }

    // MARK: - Reading Numbers output

    func testSnapshotOutputIsParsedWithTypesEscapesAndMissingValues() throws {
        let output = [
            "S\t2\t3",
            "1\t1\tT\tDate\t+\tDate\tautomatic",
            "1\t2\tT\tSecurity\t+\tSecurity\tautomatic",
            "1\t3\tE\t\t-\t\tautomatic",
            "2\t1\tD\t2026-9-3\t+\t9/3/2026\tdate and time",
            "2\t2\tT\tA\\tB\\\\C\\nD\t+\tA\\tB\\\\C\\nD\ttext",
            "2\t3\tN\t7.36\t+\t$7.36\tcurrency",
        ].joined(separator: "\n")
        let snapshot = try parseSheetSnapshot(output)
        XCTAssertEqual(snapshot.rowCount, 2)
        XCTAssertEqual(snapshot.rows[0][2], SheetCell(value: .empty, formatted: nil, format: .automatic))
        XCTAssertEqual(snapshot.rows[1][0], SheetCell(value: .date(date(2026, 9, 3)), formatted: "9/3/2026", format: .dateAndTime))
        XCTAssertEqual(snapshot.rows[1][1].value, .text("A\tB\\C\nD"))
        XCTAssertEqual(snapshot.rows[1][2], SheetCell(value: .number(dec("7.36")), formatted: "$7.36", format: .currency))
        XCTAssertEqual(snapshot.headers, ["Date", "Security", ""])
    }

    func testIncompleteOrMalformedSnapshotOutputIsRejected() {
        assertSheetError(.malformedSnapshot, try parseSheetSnapshot("S\t1\t2\n1\t1\tT\tDate\t+\tDate\tautomatic"))
        assertSheetError(.malformedSnapshot, try parseSheetSnapshot("S\t1\t1\n1\t1\tD\t2026-2-30\t+\tx\tdate and time"))
        assertSheetError(.malformedSnapshot, try parseSheetSnapshot("S\t1\t1\n1\t1\tN\tabc\t+\tx\tnumber"))
        assertSheetError(.malformedSnapshot, try parseSheetSnapshot("1\t1\tT\tDate\t+\tDate\tautomatic"))
    }

    // MARK: - Writing script

    func testWriteScriptInsertsRowsAndSetsTypedValues() throws {
        let plan = SheetUpdatePlan(placement: .insertBelow(row: 614), rows: [
            PlannedRow(values: [1: .text("E*Trade \"Financial\""), 4: .date(date(2026, 9, 28)), 6: .number(dec("3.39")), 7: .empty], displays: [:]),
            PlannedRow(values: [6: .number(dec("-1.5"))], displays: [:]),
        ], templateRequirements: [:])
        let script = try numbersWriteScript(workbookPath: "/tmp/Ledger.numbers", sheetName: "Sheet 1", plan: plan)
        XCTAssertTrue(script.contains("add row below row 614 of t"))
        XCTAssertTrue(script.contains("add row below row 615 of t"))
        XCTAssertTrue(script.contains("set value of cell 1 of row 615 of t to \"E*Trade \\\"Financial\\\"\""))
        XCTAssertTrue(script.contains("set year of targetDate to 2026"))
        XCTAssertTrue(script.contains("set month of targetDate to September"))
        XCTAssertTrue(script.contains("set value of cell 4 of row 615 of t to targetDate"))
        XCTAssertTrue(script.contains("set value of cell 6 of row 615 of t to 3.39"))
        XCTAssertTrue(script.contains("set value of cell 7 of row 615 of t to missing value"))
        XCTAssertTrue(script.contains("set value of cell 6 of row 616 of t to -1.5"))
        XCTAssertTrue(script.contains("table 1 of sheet \"Sheet 1\""))
        XCTAssertTrue(script.contains("save d"))
    }

    func testWriteScriptReappliesCurrencyFormatAfterWritingAmounts() throws {
        // Numbers resets an inherited currency format when a number is written into the cell.
        let plan = SheetUpdatePlan(placement: .insertBelow(row: 3), rows: [
            PlannedRow(values: [1: .date(date(2026, 9, 28)), 3: .number(dec("3.39"))], displays: [:]),
        ], templateRequirements: [1: .dateOnly(.monthDayFullYear), 3: .currency])
        let script = try numbersWriteScript(workbookPath: "/tmp/x.numbers", sheetName: "S", plan: plan)
        let value = try XCTUnwrap(script.range(of: "set value of cell 3 of row 4 of t to 3.39"))
        let format = try XCTUnwrap(script.range(of: "set format of cell 3 of row 4 of t to currency"))
        XCTAssertLessThan(value.lowerBound, format.lowerBound)
        XCTAssertFalse(script.contains("set format of cell 1"))
    }

    func testWriteScriptReplacesWithoutAddingRowsAndAddsAboveForInsertAbove() throws {
        let replace = SheetUpdatePlan(placement: .replace(row: 2), rows: [PlannedRow(values: [2: .text("A")], displays: [:])], templateRequirements: [:])
        let replaceScript = try numbersWriteScript(workbookPath: "/tmp/x.numbers", sheetName: "S", plan: replace)
        XCTAssertFalse(replaceScript.contains("add row"))
        XCTAssertTrue(replaceScript.contains("set value of cell 2 of row 2 of t to \"A\""))

        let above = SheetUpdatePlan(placement: .insertAbove(row: 2), rows: [PlannedRow(values: [2: .text("A")], displays: [:])], templateRequirements: [:])
        let aboveScript = try numbersWriteScript(workbookPath: "/tmp/x.numbers", sheetName: "S", plan: above)
        XCTAssertTrue(aboveScript.contains("add row above row 2 of t"))
        XCTAssertTrue(aboveScript.contains("set value of cell 2 of row 2 of t to \"A\""))
    }

    func testScriptsWaitForTheDocumentToOpen() throws {
        let opener = numbersOpenDocumentScript(path: "/tmp/x.numbers")
        XCTAssertTrue(opener.contains("open POSIX file \"/tmp/x.numbers\""))
        XCTAssertTrue(opener.contains("if d is missing value then error"))
        XCTAssertTrue(numbersSnapshotScript(workbookPath: "/tmp/x.numbers", sheetName: "S").contains(opener))
    }

    // MARK: - Mail backlog

    func testMailListingIsParsedOldestFirst() throws {
        let output = "41\tACCT\t<b@example.invalid>\t-3600\n40\tACCT\t<a@example.invalid>\t-86400\n42\tACCT\t<c@example.invalid>\t-60"
        let refs = try parseMailListing(output)
        XCTAssertEqual(refs.map(\.id), [40, 41, 42])
        XCTAssertEqual(refs.first, MailMessageRef(id: 40, accountID: "ACCT", rfcMessageID: "<a@example.invalid>", ageOffset: -86400))
        XCTAssertEqual(try parseMailListing(""), [])
        assertSheetError(.malformedMailListing, try parseMailListing("x\tACCT\t<a>\t-1"))
    }

    func testMailListingIsLimitedToTheICloudAccount() throws {
        let script = try mailListingScript(MailQuery(subjectContains: "Dividend or interest paid", senderContains: "etrade.com"))
        XCTAssertTrue(script.contains("whose subject contains \"Dividend or interest paid\" and sender contains \"etrade.com\""))
        XCTAssertTrue(script.contains("server name of account of mailbox of m is \"imap.mail.me.com\""))
        XCTAssertThrowsError(try mailListingScript(MailQuery(subjectContains: "", senderContains: nil)))
        XCTAssertThrowsError(try mailListingScript(MailQuery(subjectContains: "a\nb", senderContains: nil)))
    }

    func testProcessingStopsAtTheFirstFailure() {
        struct Boom: Error {}
        var processed: [Int] = []
        XCTAssertThrowsError(try processInOrder([1, 2, 3]) { item in
            processed.append(item)
            if item == 2 { throw Boom() }
        })
        XCTAssertEqual(processed, [1, 2])
    }

    // MARK: - Backups

    func testBackupNameIsTimestampedAndSequenced() {
        let url = backupURL(directory: URL(fileURLWithPath: "/tmp/backups"),
                            workbook: URL(fileURLWithPath: "/x/Dividend or Interest Paid.numbers"),
                            timestamp: Date(timeIntervalSince1970: 1_790_000_000), sequence: 2)
        XCTAssertEqual(url.path, "/tmp/backups/Dividend or Interest Paid-backup-20260921T141320Z-2.numbers")
    }
}

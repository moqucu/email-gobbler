import Foundation
import MailNumbersCore

/// Problems that would stop a ledger update, phrased as what to fix in Numbers.
public func checkDividendLedger(_ sheet: SheetSnapshot) -> [String] {
    let headers = sheet.headers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    let missing = DividendLedger.headers.filter { name in headers.filter { $0 == name }.count != 1 }
    guard missing.isEmpty else { return ["Missing columns: " + missing.joined(separator: ", ")] }
    guard let lastRow = (2...max(sheet.rowCount, 2)).last(where: { row in
        row <= sheet.rowCount && sheet.rows[row - 1].contains { $0.value != .empty }
    }) else {
        return ["Enter the first payment by hand so new rows can copy its formatting"]
    }
    let dateColumn = headers.firstIndex(of: "Date")! + 1
    let amountColumn = headers.firstIndex(of: "Amount Credited")! + 1
    var problems: [String] = []
    if let cell = sheet.cell(row: lastRow, column: dateColumn), !FormatRequirement.dateOnly(.monthDayFullYear).isSatisfied(by: cell) {
        problems.append("Format the Date column like 9/21/2026 (row \(lastRow))")
    }
    if let cell = sheet.cell(row: lastRow, column: amountColumn), !FormatRequirement.currency.isSatisfied(by: cell) {
        problems.append("Format Amount Credited as Currency (row \(lastRow))")
    }
    return problems
}

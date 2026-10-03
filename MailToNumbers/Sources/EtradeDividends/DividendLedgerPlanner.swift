import Foundation
import MailNumbersCore

public enum DividendLedger {
    public static let institution = "E*Trade Financial"
    public static let paymentType = "Dividend or Interest Paid"
    public static let headers = ["Financial Institution", "Account", "Type", "Date", "Security", "Amount Credited"]
}

public enum DividendLedgerError: Error, Equatable {
    case notImplemented
    case unexpectedHeaders
    case unsupportedAccount(String)
    case noTemplateRow
}

public struct DividendLedgerPlan: Equatable {
    public let update: SheetUpdatePlan
    /// Payments whose identical row is already in the ledger.
    public let alreadyRecorded: [DividendPayment]

    public init(update: SheetUpdatePlan, alreadyRecorded: [DividendPayment]) {
        self.update = update
        self.alreadyRecorded = alreadyRecorded
    }
}

/// The ledger masks accounts as "XXXX-" plus the last four digits.
public func normalizedAccount(_ mask: String) throws -> String {
    let trimmed = mask.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.range(of: "^X+-[0-9]{4}$", options: .regularExpression) != nil else {
        throw DividendLedgerError.unsupportedAccount(mask)
    }
    return "XXXX-" + trimmed.suffix(4)
}

private func collapsed(_ text: String) -> String {
    text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func sameCents(_ a: Decimal, _ b: Decimal) -> Bool {
    let difference = a - b
    return difference < Decimal(string: "0.005")! && difference > Decimal(string: "-0.005")!
}

/// Appends an alert's unrecorded payments below the ledger's last non-empty row.
public func planDividendLedgerUpdate(alert: DividendAlert, sheet: SheetSnapshot) throws -> DividendLedgerPlan {
    let headers = sheet.headers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    var column: [String: Int] = [:]
    for name in DividendLedger.headers {
        let positions = headers.indices.filter { headers[$0] == name }
        guard positions.count == 1 else { throw DividendLedgerError.unexpectedHeaders }
        column[name] = positions[0] + 1
    }
    let institutionColumn = column["Financial Institution"]!, accountColumn = column["Account"]!
    let typeColumn = column["Type"]!, dateColumn = column["Date"]!
    let securityColumn = column["Security"]!, amountColumn = column["Amount Credited"]!

    let account = try normalizedAccount(alert.accountMask)

    guard let lastRow = (2...max(sheet.rowCount, 2)).last(where: { row in
        row <= sheet.rowCount && sheet.rows[row - 1].contains { $0.value != .empty }
    }) else { throw DividendLedgerError.noTemplateRow }

    func isRecorded(_ payment: DividendPayment) -> Bool {
        (2...lastRow).contains { row in
            guard sheet.cell(row: row, column: accountColumn)?.value == .text(account),
                  sheet.cell(row: row, column: dateColumn)?.value == .date(alert.paymentDate),
                  case .text(let security)? = sheet.cell(row: row, column: securityColumn)?.value,
                  collapsed(security) == collapsed(payment.security),
                  case .number(let amount)? = sheet.cell(row: row, column: amountColumn)?.value else { return false }
            return sameCents(amount, payment.amount)
        }
    }

    var rows: [PlannedRow] = []
    var recorded: [DividendPayment] = []
    let dateStyle = DateDisplayStyle.monthDayFullYear
    for payment in alert.payments {
        if isRecorded(payment) {
            recorded.append(payment)
            continue
        }
        rows.append(PlannedRow(
            values: [institutionColumn: .text(DividendLedger.institution), accountColumn: .text(account),
                     typeColumn: .text(DividendLedger.paymentType), dateColumn: .date(alert.paymentDate),
                     securityColumn: .text(collapsed(payment.security)), amountColumn: .number(payment.amount)],
            displays: [dateColumn: .exact(dateStyle.display(alert.paymentDate)),
                       amountColumn: .exact(currencyDisplay(payment.amount))]
        ))
    }
    return DividendLedgerPlan(
        update: SheetUpdatePlan(placement: .insertBelow(row: lastRow), rows: rows,
                                templateRequirements: [dateColumn: .dateOnly(dateStyle), amountColumn: .currency]),
        alreadyRecorded: recorded
    )
}

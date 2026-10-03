import Foundation
import MailNumbersCore

/// E*TRADE "Dividend or interest paid" alerts into the dividend ledger.
public struct EtradeDividendsUseCase: MailToNumbersUseCase {
    public static let defaultQuery = MailQuery(subjectContains: "Dividend or interest paid", senderContains: "etrade.com")
    public static let defaultSheetName = "Sheet 1"

    public let mailQuery: MailQuery

    public init(mailQuery: MailQuery = defaultQuery) {
        self.mailQuery = mailQuery
    }

    public func summarize(html: String) throws -> [String] {
        let alert = try parseEtradeDividendAlert(html: html)
        return ["Account: \(alert.accountMask)",
                "Paid: \(DateDisplayStyle.monthDayFullYear.display(alert.paymentDate))",
                "Payments: \(alert.payments.count)"]
            + alert.payments.map { "  \($0.security): \(currencyDisplay($0.amount))" }
    }

    public func plan(html: String, sheet: SheetSnapshot) throws -> UseCasePlan {
        let planned = try planDividendLedgerUpdate(alert: try parseEtradeDividendAlert(html: html), sheet: sheet)
        return UseCasePlan(update: planned.update, notes: planned.alreadyRecorded.map {
            "Already recorded: \($0.security) \(currencyDisplay($0.amount))"
        })
    }
}

import Foundation
import MailNumbersCore

/// E*TRADE "Dividend or interest paid" alerts into the dividend ledger.
public struct EtradeDividendsUseCase: MailToNumbersUseCase {
    public static let defaultQuery = MailQuery(subjectContains: "Dividend or interest paid", senderContains: "etrade.com")
    public static let defaultSheetName = "Sheet 1"

    public let mailQuery: MailQuery
    public let target: SheetTarget?

    public init(target: SheetTarget?, mailQuery: MailQuery = defaultQuery) {
        self.target = target
        self.mailQuery = mailQuery
    }

    public var targets: [SheetTarget] { [] }

    public func summarize(html: String) throws -> [String] {
        let alert = try parseEtradeDividendAlert(html: html)
        return ["Account: \(alert.accountMask)",
                "Paid: \(DateDisplayStyle.monthDayFullYear.display(alert.paymentDate))",
                "Payments: \(alert.payments.count)"]
            + alert.payments.map { "  \($0.security): \(currencyDisplay($0.amount))" }
    }

    public func plan(html: String, sheets: [SheetTarget: SheetSnapshot]) throws -> UseCasePlan {
        throw DividendLedgerError.noTemplateRow
    }
}

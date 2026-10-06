import EmailGobblerCore
import Foundation
import GnuCashBook

extension SpendingEmailError: EmailApplicability {
    public var leavesEmailInInbox: Bool {
        if case .notApplicable = self { return true }
        return false
    }
}

/// American Express "Your Card may not have been present for a purchase" alerts into the card account.
public struct AmexPurchasesUseCase: GnuCashUseCase {
    public static let defaultQuery = MailQuery(subjectContains: "purchase", senderContains: "americanexpress.com")

    public let mailQuery: MailQuery
    public let bookURL: URL?
    public let amexAccount: String
    public let holdingAccount: String

    public init(bookURL: URL?, amexAccount: String, holdingAccount: String, mailQuery: MailQuery = defaultQuery) {
        self.bookURL = bookURL
        self.amexAccount = amexAccount
        self.holdingAccount = holdingAccount
        self.mailQuery = mailQuery
    }

    public var targets: [SheetTarget] { [] }

    public func summarize(html: String) throws -> [String] {
        let purchase = try parseAmexPurchaseAlert(html: html)
        return ["Merchant: \(purchase.merchant)", "Amount: \(currencyDisplay(purchase.amount))",
                "Date: \(DateDisplayStyle.monthDayFullYear.display(purchase.date))"]
    }

    public func plan(html: String, sheets: [SheetTarget: SheetSnapshot]) throws -> UseCasePlan { UseCasePlan(targets: [], notes: []) }

    public func planBook(html: String, book: GnuCashBook) throws -> GnuCashPlan {
        let planned = try planAmexPurchase(try parseAmexPurchaseAlert(html: html), book: book, amexAccount: amexAccount,
                                           holdingAccount: holdingAccount)
        return GnuCashPlan(transactions: planned.transactions, notes: planned.notes)
    }
}

/// PayPal payment receipts into the PayPal account, with the funding collection.
public struct PayPalPaymentsUseCase: GnuCashUseCase {
    public static let defaultQuery = MailQuery(subjectContains: "USD", senderContains: "paypal.com")

    public let mailQuery: MailQuery
    public let bookURL: URL?
    public let accounts: PayPalAccounts
    public let holdingAccount: String

    public init(bookURL: URL?, accounts: PayPalAccounts, holdingAccount: String, mailQuery: MailQuery = defaultQuery) {
        self.bookURL = bookURL
        self.accounts = accounts
        self.holdingAccount = holdingAccount
        self.mailQuery = mailQuery
    }

    public var targets: [SheetTarget] { [] }

    public func summarize(html: String) throws -> [String] {
        let payment = try parsePayPalReceipt(html: html)
        let sources = payment.funding.count
        return ["Merchant: \(payment.merchant)", "Amount: \(currencyDisplay(payment.amount))",
                "Date: \(DateDisplayStyle.monthDayFullYear.display(payment.date))",
                "Funding: \(sources) source\(sources == 1 ? "" : "s")"]
    }

    public func plan(html: String, sheets: [SheetTarget: SheetSnapshot]) throws -> UseCasePlan { UseCasePlan(targets: [], notes: []) }

    public func planBook(html: String, book: GnuCashBook) throws -> GnuCashPlan {
        let planned = try planPayPalPayment(try parsePayPalReceipt(html: html), book: book, accounts: accounts,
                                            holdingAccount: holdingAccount)
        return GnuCashPlan(transactions: planned.transactions, notes: planned.notes)
    }
}

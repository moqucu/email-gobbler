import EmailGobblerCore
import Foundation
import GnuCashBook

public struct AmexPurchase: Equatable, Sendable {
    public let merchant: String
    public let amount: Decimal
    public let date: CalendarDate
    public let accountEnding: String?

    public init(merchant: String, amount: Decimal, date: CalendarDate, accountEnding: String?) {
        self.merchant = merchant
        self.amount = amount
        self.date = date
        self.accountEnding = accountEnding
    }
}

public struct PayPalFunding: Equatable, Sendable {
    public let source: String
    public let amount: Decimal

    public init(source: String, amount: Decimal) {
        self.source = source
        self.amount = amount
    }
}

public struct PayPalPayment: Equatable, Sendable {
    public let merchant: String
    public let amount: Decimal
    public let currency: String
    public let date: CalendarDate
    public let transactionID: String
    public let funding: [PayPalFunding]

    public init(merchant: String, amount: Decimal, currency: String, date: CalendarDate, transactionID: String,
                funding: [PayPalFunding]) {
        self.merchant = merchant
        self.amount = amount
        self.currency = currency
        self.date = date
        self.transactionID = transactionID
        self.funding = funding
    }
}

public enum SpendingEmailError: Error, Equatable, CustomStringConvertible {
    case notImplemented
    /// The email is from the sender but is not a purchase; it is left in the Inbox.
    case notApplicable(String)
    case missingField(String)
    case malformedAmount(String)
    case invalidDate(String)
    case unsupportedCurrency(String)
    case unsupportedFunding(String)

    public var description: String {
        switch self {
        case .notImplemented: return "Not implemented"
        case .notApplicable(let reason): return reason
        case .missingField(let field): return "The email has no \(field)"
        case .malformedAmount(let text): return "The amount \"\(text)\" could not be read"
        case .invalidDate(let text): return "The date \"\(text)\" could not be read"
        case .unsupportedCurrency(let code): return "Payments in \(code) are not supported yet"
        case .unsupportedFunding(let source): return "Unknown PayPal funding source \"\(source)\""
        }
    }
}

public func parseAmexPurchaseAlert(html: String) throws -> AmexPurchase { throw SpendingEmailError.notImplemented }
public func parsePayPalReceipt(html: String) throws -> PayPalPayment { throw SpendingEmailError.notImplemented }

/// What to add to the book for one email, and what was skipped.
public struct SpendingPlan: Equatable, Sendable {
    public let transactions: [NewGnuCashTransaction]
    public let notes: [String]

    public init(transactions: [NewGnuCashTransaction], notes: [String]) {
        self.transactions = transactions
        self.notes = notes
    }
}

public struct PayPalAccounts: Equatable, Sendable {
    public let payPal: String
    public let bankFunding: String
    public let cardFunding: String

    public init(payPal: String, bankFunding: String, cardFunding: String) {
        self.payPal = payPal
        self.bankFunding = bankFunding
        self.cardFunding = cardFunding
    }
}

public func planAmexPurchase(_ purchase: AmexPurchase, book: GnuCashBook, amexAccount: String,
                             holdingAccount: String) throws -> SpendingPlan {
    throw SpendingEmailError.notImplemented
}

public func planPayPalPayment(_ payment: PayPalPayment, book: GnuCashBook, accounts: PayPalAccounts,
                              holdingAccount: String) throws -> SpendingPlan {
    throw SpendingEmailError.notImplemented
}

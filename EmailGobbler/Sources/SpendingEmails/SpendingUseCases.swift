import EmailGobblerCore
import Foundation
import GnuCashBook

extension SpendingEmailError: EmailApplicability {
    public var leavesEmailInInbox: Bool { false }
}

/// American Express "Your Card may not have been present for a purchase" alerts into the card account.
public struct AmexPurchasesUseCase: GnuCashUseCase {
    public static let defaultQuery = MailQuery(subjectContains: "", senderContains: nil)

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
    public func summarize(html: String) throws -> [String] { [] }
    public func plan(html: String, sheets: [SheetTarget: SheetSnapshot]) throws -> UseCasePlan { UseCasePlan(targets: [], notes: []) }
    public func planBook(html: String, book: GnuCashBook) throws -> GnuCashPlan { GnuCashPlan(transactions: [], notes: []) }
}

/// PayPal payment receipts into the PayPal account, with the funding collection.
public struct PayPalPaymentsUseCase: GnuCashUseCase {
    public static let defaultQuery = MailQuery(subjectContains: "", senderContains: nil)

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
    public func summarize(html: String) throws -> [String] { [] }
    public func plan(html: String, sheets: [SheetTarget: SheetSnapshot]) throws -> UseCasePlan { UseCasePlan(targets: [], notes: []) }
    public func planBook(html: String, book: GnuCashBook) throws -> GnuCashPlan { GnuCashPlan(transactions: [], notes: []) }
}

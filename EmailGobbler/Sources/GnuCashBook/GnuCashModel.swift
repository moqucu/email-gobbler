import EmailGobblerCore
import Foundation

public struct GnuCashCommodity: Hashable, Sendable, CustomStringConvertible {
    public let space: String
    public let id: String

    public init(space: String, id: String) {
        self.space = space
        self.id = id
    }

    public var isCurrency: Bool { space == "CURRENCY" || space == "ISO4217" }
    public var description: String { id }
}

public struct GnuCashAccount: Equatable, Sendable {
    public let guid: String
    public let name: String
    /// Names from the top-level account down, joined with ":", without the root.
    public let fullName: String
    public let type: String
    public let commodity: GnuCashCommodity?
    public let commoditySCU: Int?
    public let parentGUID: String?
    public let isPlaceholder: Bool

    public init(guid: String, name: String, fullName: String, type: String, commodity: GnuCashCommodity?,
                commoditySCU: Int?, parentGUID: String?, isPlaceholder: Bool) {
        self.guid = guid
        self.name = name
        self.fullName = fullName
        self.type = type
        self.commodity = commodity
        self.commoditySCU = commoditySCU
        self.parentGUID = parentGUID
        self.isPlaceholder = isPlaceholder
    }
}

public struct GnuCashSplit: Equatable, Sendable {
    public let guid: String
    public let accountGUID: String
    public let value: Decimal
    public let quantity: Decimal
    public let memo: String?
    public let reconciledState: String

    public init(guid: String, accountGUID: String, value: Decimal, quantity: Decimal, memo: String?, reconciledState: String) {
        self.guid = guid
        self.accountGUID = accountGUID
        self.value = value
        self.quantity = quantity
        self.memo = memo
        self.reconciledState = reconciledState
    }
}

public struct GnuCashTransaction: Equatable, Sendable {
    public let guid: String
    public let currency: GnuCashCommodity
    public let num: String?
    public let datePosted: CalendarDate
    public let dateEntered: Date
    public let description: String
    public let splits: [GnuCashSplit]

    public init(guid: String, currency: GnuCashCommodity, num: String?, datePosted: CalendarDate, dateEntered: Date,
                description: String, splits: [GnuCashSplit]) {
        self.guid = guid
        self.currency = currency
        self.num = num
        self.datePosted = datePosted
        self.dateEntered = dateEntered
        self.description = description
        self.splits = splits
    }
}

/// The parts of a GnuCash book that EmailGobbler reads: accounts outside the
/// scheduled-transaction templates, and ordinary transactions.
public struct GnuCashBook: Sendable {
    public let bookGUID: String
    public let accounts: [GnuCashAccount]
    public let transactions: [GnuCashTransaction]

    public init(bookGUID: String, accounts: [GnuCashAccount], transactions: [GnuCashTransaction]) {
        self.bookGUID = bookGUID
        self.accounts = accounts
        self.transactions = transactions
    }

    public func account(named fullName: String) -> GnuCashAccount? { nil }
    public func account(guid: String) -> GnuCashAccount? { nil }
}

/// A balanced transaction to append. Amounts are positive for debits and
/// negative for credits, in the accounts' currency.
public struct NewGnuCashSplit: Equatable, Sendable {
    public let accountName: String
    public let amount: Decimal
    public let memo: String?

    public init(accountName: String, amount: Decimal, memo: String? = nil) {
        self.accountName = accountName
        self.amount = amount
        self.memo = memo
    }
}

public struct NewGnuCashTransaction: Equatable, Sendable {
    public let date: CalendarDate
    public let description: String
    public let num: String?
    public let splits: [NewGnuCashSplit]

    public init(date: CalendarDate, description: String, num: String? = nil, splits: [NewGnuCashSplit]) {
        self.date = date
        self.description = description
        self.num = num
        self.splits = splits
    }
}

public enum GnuCashError: Error, Equatable, CustomStringConvertible {
    case notImplemented
    case corruptCompressedData
    case notAGnuCashBook
    case malformedBook(String)
    case unknownAccount(String)
    case placeholderAccount(String)
    case notACurrencyAccount(String)
    case mixedCurrencies
    case needsTwoSplits
    case unbalanced(Decimal)
    case tooPrecise(account: String, amount: Decimal)
    case bookOpenInGnuCash(String)
    case verificationFailed(String)

    public var description: String {
        switch self {
        case .notImplemented: return "Not implemented"
        case .corruptCompressedData: return "The compressed GnuCash file is damaged"
        case .notAGnuCashBook: return "The file is not a GnuCash XML book"
        case .malformedBook(let detail): return "The GnuCash book is malformed: \(detail)"
        case .unknownAccount(let name): return "No GnuCash account named \"\(name)\""
        case .placeholderAccount(let name): return "\"\(name)\" is a placeholder account and cannot hold transactions"
        case .notACurrencyAccount(let name): return "\"\(name)\" holds a security, not a currency"
        case .mixedCurrencies: return "All accounts in a transaction must use the same currency"
        case .needsTwoSplits: return "A transaction needs at least two splits"
        case .unbalanced(let difference): return "The splits do not balance; they differ by \(difference)"
        case .tooPrecise(let account, let amount):
            return "\(amount) has more decimal places than \"\(account)\" allows"
        case .bookOpenInGnuCash(let name): return "Close \(name) in GnuCash; it will be updated on the next run"
        case .verificationFailed(let detail): return "The saved GnuCash book did not verify: \(detail)"
        }
    }
}

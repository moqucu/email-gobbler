import EmailGobblerCore
import Foundation

public struct GnuCashPlan: Equatable, Sendable {
    public let transactions: [NewGnuCashTransaction]
    public let notes: [String]

    public init(transactions: [NewGnuCashTransaction], notes: [String]) {
        self.transactions = transactions
        self.notes = notes
    }
}

/// An email use case that records transactions in a GnuCash book.
public protocol GnuCashUseCase: EmailUseCase {
    /// The book to read and append to; without one a run only summarizes.
    var bookURL: URL? { get }
    func planBook(html: String, book: GnuCashBook) throws -> GnuCashPlan
}

public struct BookActions {
    public var readBook: ((URL) throws -> GnuCashBook)?
    public var append: ((URL, [NewGnuCashTransaction]) throws -> Void)?
    public var consume: (() throws -> Void)?

    public init(readBook: ((URL) throws -> GnuCashBook)? = nil,
                append: ((URL, [NewGnuCashTransaction]) throws -> Void)? = nil,
                consume: (() throws -> Void)? = nil) {
        self.readBook = readBook
        self.append = append
        self.consume = consume
    }
}

/// One line per planned transaction, for previews; it contains amounts, so keep it out of logs.
public func describe(_ transaction: NewGnuCashTransaction) -> String { "" }

public func processBookMessage(html: String, useCase: some GnuCashUseCase, actions: BookActions) throws -> MessageReport {
    throw WorkflowError.invalidActions
}

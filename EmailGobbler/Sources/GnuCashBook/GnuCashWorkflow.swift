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
public func describe(_ transaction: NewGnuCashTransaction) -> String {
    let date = transaction.date
    let num = transaction.num.map { " #\($0)" } ?? ""
    let splits = transaction.splits.map { "\($0.accountName) \($0.amount)" }.joined(separator: " | ")
    return "\(date.month)/\(date.day)/\(date.year)\(num) \(transaction.description): \(splits)"
}

/// Summarizes one decoded email and, when actions allow, reads the book, plans
/// its transactions, appends them, and consumes the message only after the
/// append succeeded (or the book already holds the email's transactions).
public func processBookMessage(html: String, useCase: some GnuCashUseCase, actions: BookActions) throws -> MessageReport {
    guard actions.consume == nil || actions.append != nil, actions.append == nil || actions.readBook != nil else {
        throw WorkflowError.invalidActions
    }
    let summary = try useCase.summarize(html: html)
    guard let readBook = actions.readBook, let bookURL = useCase.bookURL else {
        return MessageReport(summary: summary, notes: [], targets: [], consumed: false)
    }
    let planned = try useCase.planBook(html: html, book: try readBook(bookURL))
    let preview = planned.transactions.map(describe)
    guard let append = actions.append else {
        return MessageReport(summary: summary, notes: planned.notes, targets: [], consumed: false,
                             ledgerEntries: 0, ledgerPreview: preview)
    }
    if !planned.transactions.isEmpty { try append(bookURL, planned.transactions) }
    try actions.consume?()
    return MessageReport(summary: summary, notes: planned.notes, targets: [], consumed: actions.consume != nil,
                         ledgerEntries: planned.transactions.count, ledgerPreview: preview)
}

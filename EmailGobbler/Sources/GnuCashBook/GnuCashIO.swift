import EmailGobblerCore
import Foundation

public enum Gzip {
    public static func isCompressed(_ data: Data) -> Bool { false }
    public static func decompress(_ data: Data) throws -> Data { throw GnuCashError.notImplemented }
    public static func compress(_ data: Data) -> Data { data }
}

public func parseGnuCashBook(_ xml: Data) throws -> GnuCashBook { throw GnuCashError.notImplemented }

/// Returns `xml` with `transactions` inserted after the existing transactions
/// and the transaction count updated; the rest of the text is unchanged.
public func appendingTransactions(_ transactions: [NewGnuCashTransaction], toBookXML xml: String, book: GnuCashBook,
                                  enteredAt: Date, makeGUID: () -> String) throws -> String {
    throw GnuCashError.notImplemented
}

/// A GnuCash XML book on disk, compressed or not.
public struct GnuCashBookStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public var lockURL: URL { url }

    public func load() throws -> GnuCashBook { throw GnuCashError.notImplemented }

    /// Backs up the book, appends the transactions, writes atomically, and
    /// verifies the saved book. Refuses while GnuCash has the book open.
    @discardableResult
    public func append(_ transactions: [NewGnuCashTransaction], backupDirectory: URL, now: Date = Date(),
                       makeGUID: () -> String = defaultGUID) throws -> [String] {
        throw GnuCashError.notImplemented
    }
}

public func defaultGUID() -> String {
    UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
}

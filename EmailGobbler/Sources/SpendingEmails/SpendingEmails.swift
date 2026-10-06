import EmailGobblerCore
import Foundation
import GnuCashBook
import SwiftSoup

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
    /// The email is from the sender but is not a purchase; it is left in the Inbox.
    case notApplicable(String)
    case missingField(String)
    case malformedAmount(String)
    case invalidDate(String)
    case unsupportedCurrency(String)
    case unsupportedFunding(String)

    public var description: String {
        switch self {
        case .notApplicable(let reason): return reason
        case .missingField(let field): return "The email has no \(field)"
        case .malformedAmount(let text): return "The amount \"\(text)\" could not be read"
        case .invalidDate(let text): return "The date \"\(text)\" could not be read"
        case .unsupportedCurrency(let code): return "Payments in \(code) are not supported yet"
        case .unsupportedFunding(let source): return "Unknown PayPal funding source \"\(source)\""
        }
    }
}

// MARK: - Parsing

private func collapsed(_ text: String) -> String {
    text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func matches(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
}

private let months = ["Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
                      "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12]

/// Reads "Mar 12, 2026", optionally preceded by a weekday such as "Thu, ".
private func emailDate(_ text: String) throws -> CalendarDate {
    let parts = text.replacingOccurrences(of: ",", with: " ").split(separator: " ").map(String.init)
    let tail = Array(parts.suffix(3))
    guard tail.count == 3, let month = months[tail[0]], let day = Int(tail[1]), let year = Int(tail[2]),
          let date = try? CalendarDate(year: year, month: month, day: day) else {
        throw SpendingEmailError.invalidDate(text)
    }
    return date
}

/// Reads "$1,234.56" with an optional trailing "*" or currency code.
private func dollars(_ text: String) throws -> Decimal {
    let trimmed = text.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "USD", with: "")
        .trimmingCharacters(in: .whitespaces)
    guard matches(trimmed, "^\\$([0-9]{1,3}(,[0-9]{3})*|[0-9]+)\\.[0-9]{2}$"),
          let value = Decimal(string: trimmed.dropFirst().replacingOccurrences(of: ",", with: ""),
                              locale: Locale(identifier: "en_US_POSIX")) else {
        throw SpendingEmailError.malformedAmount(text)
    }
    return value
}

private func paragraphs(_ document: Document) -> [String] {
    ((try? document.select("p").array()) ?? []).map { collapsed((try? $0.text()) ?? "") }.filter { !$0.isEmpty }
}

/// American Express purchase alerts list the merchant, the amount, and the date
/// as consecutive paragraphs.
public func parseAmexPurchaseAlert(html: String) throws -> AmexPurchase {
    guard let document = try? SwiftSoup.parse(html) else {
        throw SpendingEmailError.notApplicable("Not an American Express purchase alert")
    }
    let lines = paragraphs(document)
    guard let index = lines.firstIndex(where: { matches($0, "^\\$[0-9][0-9,]*\\.[0-9]{2}\\*?$") }) else {
        throw SpendingEmailError.notApplicable("Not an American Express purchase alert")
    }
    guard index > 0 else { throw SpendingEmailError.missingField("merchant") }
    guard index + 1 < lines.count else { throw SpendingEmailError.missingField("date") }
    let ending = lines.first { $0.hasPrefix("Account Ending:") }
        .map { $0.dropFirst("Account Ending:".count).trimmingCharacters(in: .whitespaces) }
    return AmexPurchase(merchant: lines[index - 1], amount: try dollars(lines[index]),
                        date: try emailDate(lines[index + 1]), accountEnding: ending)
}

/// The value printed below a bold label such as "Transaction ID".
private func labelledValue(_ document: Document, _ label: String) -> String? {
    guard let strong = ((try? document.select("strong").array()) ?? []).first(where: {
        collapsed((try? $0.text()) ?? "") == label
    }) else { return nil }
    var node: Element? = strong.parent()
    while let current = node, current.tagName() != "td" { node = current.parent() }
    guard let cell = node else { return nil }
    let text = collapsed((try? cell.text()) ?? "")
    guard text.hasPrefix(label) else { return nil }
    let value = text.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
    return value.isEmpty ? nil : value
}

/// PayPal payment receipts: "You paid $X USD to Merchant", labelled details, and
/// a "Paid Merchant with" block listing each funding source and its amount.
public func parsePayPalReceipt(html: String) throws -> PayPalPayment {
    guard let document = try? SwiftSoup.parse(html),
          let headline = paragraphs(document).first(where: { $0.hasPrefix("You paid ") }),
          let toRange = headline.range(of: " to ") else {
        throw SpendingEmailError.notApplicable("Not a PayPal payment receipt")
    }
    let amountParts = headline[headline.index(headline.startIndex, offsetBy: "You paid ".count)..<toRange.lowerBound]
        .split(separator: " ").map(String.init)
    guard amountParts.count == 2 else { throw SpendingEmailError.malformedAmount(headline) }
    let currency = amountParts[1]
    guard currency == "USD" else { throw SpendingEmailError.unsupportedCurrency(currency) }
    let amount = try dollars(amountParts[0])
    let merchant = String(headline[toRange.upperBound...]).trimmingCharacters(in: .whitespaces)

    guard let transactionID = labelledValue(document, "Transaction ID") else {
        throw SpendingEmailError.missingField("Transaction ID")
    }
    guard let dateText = labelledValue(document, "Transaction date") else {
        throw SpendingEmailError.missingField("Transaction date")
    }

    var funding: [PayPalFunding] = []
    let header = ((try? document.select("td").array()) ?? []).first {
        collapsed((try? $0.ownText()) ?? "") == "Paid \(merchant) with"
    }
    if let headerRow = header?.parent(), let detailRow = try? headerRow.nextElementSibling() {
        for row in (try? detailRow.select("tr").array()) ?? [] {
            let cells = row.children().array().filter { $0.tagName() == "td" }
            guard cells.count >= 2 else { continue }
            let source = ((try? cells[0].select("p").array()) ?? []).map { collapsed((try? $0.text()) ?? "") }
                .filter { !$0.isEmpty }.joined(separator: " ")
            let amountText = collapsed((try? cells[cells.count - 1].text()) ?? "")
            guard !source.isEmpty, let value = try? dollars(amountText) else { continue }
            funding.append(PayPalFunding(source: source, amount: value))
        }
    }
    return PayPalPayment(merchant: merchant, amount: amount, currency: currency, date: try emailDate(dateText),
                         transactionID: transactionID, funding: funding)
}

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

// MARK: - Booking

private func normalized(_ name: String) -> String {
    var text = name.lowercased().replacingOccurrences(of: "www.", with: "")
    text = text.replacingOccurrences(of: "\\.(com|net|org|io|co|tv|us)\\b", with: "", options: .regularExpression)
    text = text.replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
    return collapsed(text)
}

private func sameMerchant(_ description: String, _ merchant: String) -> Bool {
    let booked = normalized(description), seen = normalized(merchant)
    guard !booked.isEmpty, !seen.isEmpty else { return false }
    return booked == seen || booked.hasPrefix(seen + " ") || seen.hasPrefix(booked + " ")
}

/// "NEW HARDWARE STORE #12" becomes "New Hardware Store #12"; mixed case stays.
private func readable(_ merchant: String) -> String {
    guard merchant == merchant.uppercased(), merchant.contains(where: \.isLetter) else { return merchant }
    return merchant.split(separator: " ").map { word in
        word.first.map { String($0) + word.dropFirst().lowercased() } ?? ""
    }.joined(separator: " ")
}

private func requireAccount(_ name: String, in book: GnuCashBook) throws -> GnuCashAccount {
    guard let account = book.account(named: name) else { throw GnuCashError.unknownAccount(name) }
    guard !account.isPlaceholder else { throw GnuCashError.placeholderAccount(name) }
    return account
}

private func dayNumber(_ date: CalendarDate) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let value = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day))!
    return Int(value.timeIntervalSince1970 / 86_400)
}

private func shown(_ date: CalendarDate) -> String { "\(date.month)/\(date.day)/\(date.year)" }

/// An existing transaction that already records this amount on the account:
/// the same transaction number, or the same signed amount within three days.
private func existingBooking(in book: GnuCashBook, account: GnuCashAccount, amount: Decimal, date: CalendarDate,
                             num: String? = nil) -> GnuCashTransaction? {
    let day = dayNumber(date)
    let onAccount = book.transactions.filter { transaction in
        transaction.splits.contains { $0.accountGUID == account.guid && $0.value == amount }
    }
    if let num, let byNum = onAccount.first(where: { $0.num == num }) { return byNum }
    return onAccount.first { abs(dayNumber($0.datePosted) - day) <= 3 }
}

private func alreadyBooked(_ transaction: GnuCashTransaction, _ amount: Decimal) -> String {
    "Already booked: \(transaction.description) \(currencyDisplay(abs(amount))) on \(shown(transaction.datePosted))"
}

/// The description and expense account of the latest booking of this merchant
/// against `account`, or a readable name and the holding account.
private func categorize(_ merchant: String, against account: GnuCashAccount, in book: GnuCashBook,
                        holdingAccount: String) throws -> (description: String, expense: String, note: String?) {
    let candidates = book.transactions.enumerated().filter { _, transaction in
        transaction.splits.contains { $0.accountGUID == account.guid } && sameMerchant(transaction.description, merchant)
    }
    let latest = candidates.max { ($0.element.datePosted, $0.offset) < ($1.element.datePosted, $1.offset) }?.element
    if let latest,
       let split = latest.splits.filter({ $0.accountGUID != account.guid }).max(by: { abs($0.value) < abs($1.value) }),
       let expense = book.account(guid: split.accountGUID), !expense.isPlaceholder, expense.type != "ROOT" {
        return (latest.description, expense.fullName, nil)
    }
    let holding = try requireAccount(holdingAccount, in: book)
    let name = readable(merchant)
    return (name, holding.fullName, "New merchant \"\(name)\" booked to \(holding.fullName)")
}

public func planAmexPurchase(_ purchase: AmexPurchase, book: GnuCashBook, amexAccount: String,
                             holdingAccount: String) throws -> SpendingPlan {
    let card = try requireAccount(amexAccount, in: book)
    if let existing = existingBooking(in: book, account: card, amount: -purchase.amount, date: purchase.date) {
        return SpendingPlan(transactions: [], notes: [alreadyBooked(existing, purchase.amount)])
    }
    let category = try categorize(purchase.merchant, against: card, in: book, holdingAccount: holdingAccount)
    return SpendingPlan(transactions: [
        NewGnuCashTransaction(date: purchase.date, description: category.description, splits: [
            NewGnuCashSplit(accountName: category.expense, amount: purchase.amount),
            NewGnuCashSplit(accountName: card.fullName, amount: -purchase.amount),
        ]),
    ], notes: category.note.map { [$0] } ?? [])
}

/// A PayPal payment is two bookings: the purchase from the PayPal account, and
/// each funding source moving the money into PayPal.
public func planPayPalPayment(_ payment: PayPalPayment, book: GnuCashBook, accounts: PayPalAccounts,
                              holdingAccount: String) throws -> SpendingPlan {
    let payPal = try requireAccount(accounts.payPal, in: book)
    var transactions: [NewGnuCashTransaction] = []
    var notes: [String] = []

    if let existing = existingBooking(in: book, account: payPal, amount: -payment.amount, date: payment.date,
                                      num: payment.transactionID) {
        notes.append(alreadyBooked(existing, payment.amount))
    } else {
        let category = try categorize(payment.merchant, against: payPal, in: book, holdingAccount: holdingAccount)
        transactions.append(NewGnuCashTransaction(date: payment.date, description: category.description,
                                                  num: payment.transactionID, splits: [
            NewGnuCashSplit(accountName: category.expense, amount: payment.amount),
            NewGnuCashSplit(accountName: payPal.fullName, amount: -payment.amount),
        ]))
        if let note = category.note { notes.append(note) }
    }

    for funding in payment.funding {
        let source = funding.source.uppercased()
        let description: String
        let sourceAccount: String
        if source.contains("AMERICAN EXPRESS") || source.contains("AMEX") {
            (description, sourceAccount) = ("AmEx - Collection", accounts.cardFunding)
        } else if source.contains("BALANCE") {
            continue
        } else if source.contains("BANK") || source.contains("CHECKING") || source.contains("SAVINGS") {
            (description, sourceAccount) = ("PayPal - Collection", accounts.bankFunding)
        } else {
            throw SpendingEmailError.unsupportedFunding(funding.source)
        }
        let from = try requireAccount(sourceAccount, in: book)
        if let existing = existingBooking(in: book, account: payPal, amount: funding.amount, date: payment.date,
                                          num: payment.transactionID) {
            notes.append(alreadyBooked(existing, funding.amount))
            continue
        }
        transactions.append(NewGnuCashTransaction(date: payment.date, description: description, num: payment.transactionID,
                                                  splits: [
            NewGnuCashSplit(accountName: payPal.fullName, amount: funding.amount),
            NewGnuCashSplit(accountName: from.fullName, amount: -funding.amount),
        ]))
    }
    return SpendingPlan(transactions: transactions, notes: notes)
}

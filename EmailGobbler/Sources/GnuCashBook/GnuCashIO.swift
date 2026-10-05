import EmailGobblerCore
import Foundation

// MARK: - Reading

private extension XMLElement {
    func children(_ name: String) -> [XMLElement] {
        (children ?? []).compactMap { $0 as? XMLElement }.filter { $0.name == name }
    }

    func child(_ name: String) -> XMLElement? { children(name).first }

    func text(_ name: String) -> String? { child(name)?.stringValue }
}

private let posix = Locale(identifier: "en_US_POSIX")

private func timestampFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = posix
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
    return formatter
}

private func calendarDate(_ text: String) -> CalendarDate? {
    let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return try? CalendarDate(year: parts[0], month: parts[1], day: parts[2])
}

private func numeric(_ text: String) -> Decimal? {
    let parts = text.split(separator: "/")
    guard parts.count == 2, let numerator = Int64(parts[0]), let denominator = Int64(parts[1]), denominator != 0 else {
        return nil
    }
    return Decimal(numerator) / Decimal(denominator)
}

private func commodity(_ element: XMLElement?) -> GnuCashCommodity? {
    guard let element, let space = element.text("cmdty:space"), let id = element.text("cmdty:id") else { return nil }
    return GnuCashCommodity(space: space, id: id)
}

private func slotValue(_ slots: XMLElement?, key: String) -> XMLElement? {
    slots?.children("slot").first { $0.text("slot:key") == key }?.child("slot:value")
}

public func parseGnuCashBook(_ data: Data) throws -> GnuCashBook {
    let xml = Gzip.isCompressed(data) ? try Gzip.decompress(data) : data
    guard let document = try? XMLDocument(data: xml), let root = document.rootElement(), root.name == "gnc-v2",
          let book = root.child("gnc:book") else {
        throw GnuCashError.notAGnuCashBook
    }
    guard let bookGUID = book.text("book:id") else { throw GnuCashError.malformedBook("book without an id") }

    struct RawAccount { let guid, name, type: String; let parent: String?; let element: XMLElement }
    let raw: [RawAccount] = try book.children("gnc:account").map { element in
        guard let guid = element.text("act:id"), let name = element.text("act:name"), let type = element.text("act:type") else {
            throw GnuCashError.malformedBook("account without an id, name, or type")
        }
        return RawAccount(guid: guid, name: name, type: type, parent: element.text("act:parent"), element: element)
    }
    let byGUID = Dictionary(raw.map { ($0.guid, $0) }, uniquingKeysWith: { first, _ in first })
    func fullName(_ account: RawAccount) -> String {
        var names: [String] = []
        var current: RawAccount? = account
        var seen = Set<String>()
        while let node = current, node.type != "ROOT", seen.insert(node.guid).inserted {
            names.insert(node.name, at: 0)
            current = node.parent.flatMap { byGUID[$0] }
        }
        return names.joined(separator: ":")
    }
    let accounts = raw.map { account in
        GnuCashAccount(
            guid: account.guid, name: account.name, fullName: fullName(account), type: account.type,
            commodity: commodity(account.element.child("act:commodity")),
            commoditySCU: account.element.text("act:commodity-scu").flatMap { Int($0) },
            parentGUID: account.parent,
            isPlaceholder: slotValue(account.element.child("act:slots"), key: "placeholder")?.stringValue == "true")
    }

    let timestamps = timestampFormatter()
    let transactions: [GnuCashTransaction] = try book.children("gnc:transaction").map { element in
        guard let guid = element.text("trn:id"), let currency = commodity(element.child("trn:currency")),
              let postedText = element.child("trn:date-posted")?.text("ts:date"),
              let enteredText = element.child("trn:date-entered")?.text("ts:date"),
              let entered = timestamps.date(from: enteredText) else {
            throw GnuCashError.malformedBook("transaction without an id, currency, or dates")
        }
        let postedSlot = slotValue(element.child("trn:slots"), key: "date-posted")?.text("gdate")
        guard let posted = postedSlot.flatMap(calendarDate) ?? timestamps.date(from: postedText).flatMap({ date in
            calendarDate(timestamps.string(from: date))
        }) else {
            throw GnuCashError.malformedBook("transaction \(guid) has an invalid posted date")
        }
        let splits: [GnuCashSplit] = try (element.child("trn:splits")?.children("trn:split") ?? []).map { split in
            guard let id = split.text("split:id"), let account = split.text("split:account"),
                  let value = split.text("split:value").flatMap(numeric),
                  let quantity = split.text("split:quantity").flatMap(numeric) else {
                throw GnuCashError.malformedBook("split without an id, account, value, or quantity")
            }
            return GnuCashSplit(guid: id, accountGUID: account, value: value, quantity: quantity,
                                memo: split.text("split:memo"), reconciledState: split.text("split:reconciled-state") ?? "n")
        }
        return GnuCashTransaction(guid: guid, currency: currency, num: element.text("trn:num"), datePosted: posted,
                                  dateEntered: entered, description: element.text("trn:description") ?? "", splits: splits)
    }
    return GnuCashBook(bookGUID: bookGUID, accounts: accounts, transactions: transactions)
}

// MARK: - Writing

private struct BookChild {
    let name: String
    let start: Int
    let end: Int
}

private func hasPrefix(_ bytes: [UInt8], _ offset: Int, _ prefix: String) -> Bool {
    let prefixBytes = Array(prefix.utf8)
    guard offset + prefixBytes.count <= bytes.count else { return false }
    return Array(bytes[offset..<offset + prefixBytes.count]) == prefixBytes
}

private func skip(_ bytes: [UInt8], from offset: Int, past terminator: String) throws -> Int {
    let target = Array(terminator.utf8)
    var index = offset
    while index + target.count <= bytes.count {
        if bytes[index] == target[0] && Array(bytes[index..<index + target.count]) == target { return index + target.count }
        index += 1
    }
    throw GnuCashError.malformedBook("unterminated markup")
}

/// Byte ranges of the direct children of `<gnc:book>` and of its closing tag.
private func scanBook(_ bytes: [UInt8]) throws -> (children: [BookChild], bookEnd: Int) {
    var index = 0
    var depth = 0
    var bookDepth: Int?
    var openChild: (name: String, start: Int)?
    var children: [BookChild] = []
    while index < bytes.count {
        guard bytes[index] == UInt8(ascii: "<") else { index += 1; continue }
        if hasPrefix(bytes, index, "<!--") { index = try skip(bytes, from: index, past: "-->"); continue }
        if hasPrefix(bytes, index, "<![CDATA[") { index = try skip(bytes, from: index, past: "]]>"); continue }
        if hasPrefix(bytes, index, "<?") { index = try skip(bytes, from: index, past: "?>"); continue }
        if hasPrefix(bytes, index, "<!") { index = try skip(bytes, from: index, past: ">"); continue }

        let start = index
        let closing = bytes[index + 1] == UInt8(ascii: "/")
        var cursor = index + (closing ? 2 : 1)
        let nameStart = cursor
        while cursor < bytes.count, !" \t\r\n/>".utf8.contains(bytes[cursor]) { cursor += 1 }
        let name = String(decoding: bytes[nameStart..<cursor], as: UTF8.self)
        var quote: UInt8?
        while cursor < bytes.count {
            let byte = bytes[cursor]
            if let open = quote {
                if byte == open { quote = nil }
            } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                quote = byte
            } else if byte == UInt8(ascii: ">") {
                break
            }
            cursor += 1
        }
        guard cursor < bytes.count else { throw GnuCashError.malformedBook("unterminated tag") }
        let selfClosing = bytes[cursor - 1] == UInt8(ascii: "/")
        index = cursor + 1

        if closing {
            depth -= 1
            if let level = bookDepth {
                if depth == level, let child = openChild {
                    children.append(BookChild(name: child.name, start: child.start, end: index))
                    openChild = nil
                } else if depth == level - 1 && name == "gnc:book" {
                    return (children, start)
                }
            }
        } else if selfClosing {
            if let level = bookDepth, depth == level {
                children.append(BookChild(name: name, start: start, end: index))
            }
        } else {
            if let level = bookDepth, depth == level { openChild = (name, start) }
            depth += 1
            if bookDepth == nil && name == "gnc:book" { bookDepth = depth }
        }
    }
    throw GnuCashError.notAGnuCashBook
}

private func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

private struct ValidatedSplit {
    let account: GnuCashAccount
    let numerator: Int64
    let denominator: Int
    let memo: String?
}

private func validate(_ transaction: NewGnuCashTransaction, in book: GnuCashBook) throws -> (GnuCashCommodity, [ValidatedSplit]) {
    guard transaction.splits.count >= 2 else { throw GnuCashError.needsTwoSplits }
    var currency: GnuCashCommodity?
    var total = Decimal(0)
    var splits: [ValidatedSplit] = []
    for split in transaction.splits {
        guard let account = book.account(named: split.accountName) else { throw GnuCashError.unknownAccount(split.accountName) }
        guard !account.isPlaceholder else { throw GnuCashError.placeholderAccount(account.fullName) }
        guard let commodity = account.commodity, commodity.isCurrency else {
            throw GnuCashError.notACurrencyAccount(account.fullName)
        }
        if let currency, currency != commodity { throw GnuCashError.mixedCurrencies }
        currency = commodity
        let denominator = account.commoditySCU ?? 100
        let scaled = split.amount * Decimal(denominator)
        let numerator = NSDecimalNumber(decimal: scaled).int64Value
        guard Decimal(numerator) == scaled else {
            throw GnuCashError.tooPrecise(account: account.fullName, amount: split.amount)
        }
        total += split.amount
        splits.append(ValidatedSplit(account: account, numerator: numerator, denominator: denominator, memo: split.memo))
    }
    guard total == 0 else { throw GnuCashError.unbalanced(total) }
    return (currency!, splits)
}

private func transactionXML(_ transaction: NewGnuCashTransaction, currency: GnuCashCommodity, splits: [ValidatedSplit],
                            entered: String, makeGUID: () -> String) -> String {
    let date = transaction.date
    let day = String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
    var lines = [
        "<gnc:transaction version=\"2.0.0\">",
        "  <trn:id type=\"guid\">\(makeGUID())</trn:id>",
        "  <trn:currency>",
        "    <cmdty:space>\(escape(currency.space))</cmdty:space>",
        "    <cmdty:id>\(escape(currency.id))</cmdty:id>",
        "  </trn:currency>",
    ]
    if let num = transaction.num, !num.isEmpty { lines.append("  <trn:num>\(escape(num))</trn:num>") }
    lines += [
        "  <trn:date-posted>",
        "    <ts:date>\(day) 10:59:00 +0000</ts:date>",
        "  </trn:date-posted>",
        "  <trn:date-entered>",
        "    <ts:date>\(entered)</ts:date>",
        "  </trn:date-entered>",
        "  <trn:description>\(escape(transaction.description))</trn:description>",
        "  <trn:slots>",
        "    <slot>",
        "      <slot:key>date-posted</slot:key>",
        "      <slot:value type=\"gdate\">",
        "        <gdate>\(day)</gdate>",
        "      </slot:value>",
        "    </slot>",
        "  </trn:slots>",
        "  <trn:splits>",
    ]
    for split in splits {
        let amount = "\(split.numerator)/\(split.denominator)"
        lines.append("    <trn:split>")
        lines.append("      <split:id type=\"guid\">\(makeGUID())</split:id>")
        if let memo = split.memo, !memo.isEmpty { lines.append("      <split:memo>\(escape(memo))</split:memo>") }
        lines += [
            "      <split:reconciled-state>n</split:reconciled-state>",
            "      <split:value>\(amount)</split:value>",
            "      <split:quantity>\(amount)</split:quantity>",
            "      <split:account type=\"guid\">\(split.account.guid)</split:account>",
            "    </trn:split>",
        ]
    }
    lines += ["  </trn:splits>", "</gnc:transaction>"]
    return lines.joined(separator: "\n") + "\n"
}

/// Elements GnuCash writes after the transactions inside `<gnc:book>`.
private func followsTransactions(_ name: String) -> Bool {
    ["gnc:template-transactions", "gnc:schedxaction", "gnc:budget"].contains(name) || name.hasPrefix("gnc:Gnc")
}

public func appendingTransactions(_ transactions: [NewGnuCashTransaction], toBookXML xml: String, book: GnuCashBook,
                                  enteredAt: Date, makeGUID: () -> String) throws -> String {
    let validated = try transactions.map { try validate($0, in: book) }
    let formatter = timestampFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let entered = formatter.string(from: enteredAt) + " +0000"
    let block = zip(transactions, validated).map { transaction, checked in
        transactionXML(transaction, currency: checked.0, splits: checked.1, entered: entered, makeGUID: makeGUID)
    }.joined()

    var bytes = Array(xml.utf8)
    let (children, bookEnd) = try scanBook(bytes)
    let insertion = children.first { followsTransactions($0.name) }?.start ?? bookEnd
    bytes.insert(contentsOf: Array(block.utf8), at: insertion)

    let total = book.transactions.count + transactions.count
    func isCount(_ child: BookChild, _ type: String) -> Bool {
        child.name == "gnc:count-data" && hasPrefix(bytes, child.start, "<gnc:count-data cd:type=\"\(type)\"")
    }
    let countLine = "<gnc:count-data cd:type=\"transaction\">\(total)</gnc:count-data>"
    if let existing = children.first(where: { isCount($0, "transaction") }) {
        bytes.replaceSubrange(existing.start..<existing.end, with: Array(countLine.utf8))
    } else if let accountCount = children.first(where: { isCount($0, "account") }) {
        var after = accountCount.end
        if after < bytes.count && bytes[after] == UInt8(ascii: "\n") { after += 1 }
        bytes.insert(contentsOf: Array((countLine + "\n").utf8), at: after)
    } else {
        throw GnuCashError.malformedBook("book without an account count")
    }
    return String(decoding: bytes, as: UTF8.self)
}

// MARK: - Book files

/// A GnuCash XML book on disk, compressed or not.
public struct GnuCashBookStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// GnuCash keeps this file while the book is open.
    public var lockURL: URL { url.appendingPathExtension("LCK") }

    public func load() throws -> GnuCashBook {
        try requireWorkbookAvailable(url)
        return try parseGnuCashBook(Data(contentsOf: url))
    }

    /// Backs up the book, appends the transactions, writes atomically, and
    /// verifies the saved book. Refuses while GnuCash has the book open and
    /// changes nothing when a transaction is invalid. Returns the new GUIDs.
    @discardableResult
    public func append(_ transactions: [NewGnuCashTransaction], backupDirectory: URL, now: Date = Date(),
                       makeGUID: () -> String = defaultGUID) throws -> [String] {
        guard !transactions.isEmpty else { return [] }
        try requireWorkbookAvailable(url)
        let manager = FileManager.default
        guard !manager.fileExists(atPath: lockURL.path) else { throw GnuCashError.bookOpenInGnuCash(url.lastPathComponent) }

        let original = try Data(contentsOf: url)
        let compressed = Gzip.isCompressed(original)
        let xmlData = compressed ? try Gzip.decompress(original) : original
        let book = try parseGnuCashBook(xmlData)
        let updatedXML = try appendingTransactions(transactions, toBookXML: String(decoding: xmlData, as: UTF8.self),
                                                   book: book, enteredAt: now, makeGUID: makeGUID)
        let expected = try parseGnuCashBook(Data(updatedXML.utf8))
        guard expected.transactions.count == book.transactions.count + transactions.count,
              Array(expected.transactions.prefix(book.transactions.count)) == book.transactions,
              expected.accounts == book.accounts else {
            throw GnuCashError.verificationFailed("the planned book does not match")
        }

        try manager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        var sequence = 1
        var backup = backupURL(directory: backupDirectory, workbook: url, timestamp: now, sequence: sequence)
        while manager.fileExists(atPath: backup.path) {
            sequence += 1
            backup = backupURL(directory: backupDirectory, workbook: url, timestamp: now, sequence: sequence)
        }
        try manager.copyItem(at: url, to: backup)

        guard !manager.fileExists(atPath: lockURL.path) else { throw GnuCashError.bookOpenInGnuCash(url.lastPathComponent) }
        let output = Data(updatedXML.utf8)
        try (compressed ? Gzip.compress(output) : output).write(to: url, options: .atomic)

        let saved = try parseGnuCashBook(Data(contentsOf: url))
        guard saved.transactions == expected.transactions, saved.accounts == expected.accounts else {
            throw GnuCashError.verificationFailed("the saved book differs from the planned book")
        }
        return expected.transactions.suffix(transactions.count).map(\.guid)
    }
}

public func defaultGUID() -> String {
    UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
}

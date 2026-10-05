import Foundation
import XCTest
import EmailGobblerCore
@testable import GnuCashBook

final class GnuCashBookTests: XCTestCase {
    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func xml() throws -> String { String(decoding: try fixture("gnucash-book.synthetic", "xml"), as: UTF8.self) }
    private func book() throws -> GnuCashBook { try parseGnuCashBook(try fixture("gnucash-book.synthetic", "xml")) }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> CalendarDate { try! CalendarDate(year: y, month: m, day: d) }
    private func dec(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }
    private let usd = GnuCashCommodity(space: "CURRENCY", id: "USD")
    private let entered = Date(timeIntervalSince1970: 1_791_127_800) // 2026-10-04 15:30:00 UTC

    private func guids() -> () -> String {
        var next = 0
        return {
            next += 1
            return String(format: "e%031d", next)
        }
    }

    private func lunch() -> NewGnuCashTransaction {
        NewGnuCashTransaction(date: date(2026, 10, 3), description: "Corner Café & <Bakery>", splits: [
            NewGnuCashSplit(accountName: "Expenses:Dining", amount: dec("12.50"), memo: "Lunch"),
            NewGnuCashSplit(accountName: "Credit Card", amount: dec("-12.50")),
        ])
    }

    private func assertGnuCashError<T>(_ expected: GnuCashError, _ expression: @autoclosure () throws -> T,
                                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? GnuCashError, expected, file: file, line: line)
        }
    }

    // MARK: - Compression

    func testGzipRoundTripAndDetection() throws {
        let text = Data(String(repeating: "GnuCash ünïcode 💶 ", count: 500).utf8)
        let compressed = Gzip.compress(text)
        XCTAssertTrue(Gzip.isCompressed(compressed))
        XCTAssertFalse(Gzip.isCompressed(text))
        XCTAssertLessThan(compressed.count, text.count)
        XCTAssertEqual(try Gzip.decompress(compressed), text)
    }

    func testGzipFileWrittenByGzipToolDecompresses() throws {
        XCTAssertEqual(try Gzip.decompress(try fixture("gnucash-book.synthetic", "gnucash")),
                       try fixture("gnucash-book.synthetic", "xml"))
    }

    func testCorruptGzipIsRejected() throws {
        var data = Gzip.compress(Data("hello".utf8))
        guard data.count > 18 else { return XCTFail("Compressed data is too short: \(data.count) bytes") }
        data[data.count - 6] ^= 0xFF
        assertGnuCashError(.corruptCompressedData, try Gzip.decompress(data))
        assertGnuCashError(.corruptCompressedData, try Gzip.decompress(Data([0x1f, 0x8b, 0x08])))
    }

    // MARK: - Reading

    func testAccountsHaveFullNamesTypesCurrencyAndPlaceholderFlags() throws {
        let book = try book()
        XCTAssertEqual(book.bookGUID, "0b0c0d0e0f101112131415161718191a")
        XCTAssertEqual(book.accounts.map(\.fullName), [
            "", "Assets", "Assets:Checking", "Credit Card", "Expenses", "Expenses:Groceries", "Expenses:Dining", "Dividends",
        ])
        let checking = try XCTUnwrap(book.account(named: "Assets:Checking"))
        XCTAssertEqual(checking, GnuCashAccount(guid: "a0000000000000000000000000000003", name: "Checking",
                                                fullName: "Assets:Checking", type: "BANK", commodity: usd, commoditySCU: 100,
                                                parentGUID: "a0000000000000000000000000000002", isPlaceholder: false))
        XCTAssertEqual(book.account(named: "Expenses")?.isPlaceholder, true)
        XCTAssertEqual(book.account(guid: "a0000000000000000000000000000001")?.type, "ROOT")
        XCTAssertNil(book.account(named: "Template Root"))
        XCTAssertNil(book.account(named: "Expenses:Travel"))
    }

    func testTransactionsHaveDatesTextAndExactSplits() throws {
        let book = try book()
        XCTAssertEqual(book.transactions.count, 2)
        XCTAssertEqual(book.transactions[0], GnuCashTransaction(
            guid: "b0000000000000000000000000000001", currency: usd, num: nil, datePosted: date(2026, 9, 28),
            dateEntered: Date(timeIntervalSince1970: 1_790_619_164), description: "Example Grocer",
            splits: [
                GnuCashSplit(guid: "c0000000000000000000000000000001", accountGUID: "a0000000000000000000000000000006",
                             value: dec("45.12"), quantity: dec("45.12"), memo: nil, reconciledState: "n"),
                GnuCashSplit(guid: "c0000000000000000000000000000002", accountGUID: "a0000000000000000000000000000004",
                             value: dec("-45.12"), quantity: dec("-45.12"), memo: "Weekly shop", reconciledState: "c"),
            ]))
        XCTAssertEqual(book.transactions[1].num, "1001")
        XCTAssertEqual(book.transactions[1].datePosted, date(2026, 9, 30))
        XCTAssertEqual(book.transactions[1].description, "Synthetic Fund Dividend")
    }

    func testCompressedAndPlainBooksReadTheSame() throws {
        let plain = try book()
        let compressed = try parseGnuCashBook(try fixture("gnucash-book.synthetic", "gnucash"))
        XCTAssertEqual(compressed.accounts, plain.accounts)
        XCTAssertEqual(compressed.transactions, plain.transactions)
    }

    func testNonGnuCashXMLIsRejected() {
        assertGnuCashError(.notAGnuCashBook, try parseGnuCashBook(Data("<html><body/></html>".utf8)))
        assertGnuCashError(.notAGnuCashBook, try parseGnuCashBook(Data("not xml".utf8)))
    }

    // MARK: - Appending

    private let expectedLunchXML = """
    <gnc:transaction version="2.0.0">
      <trn:id type="guid">e0000000000000000000000000000001</trn:id>
      <trn:currency>
        <cmdty:space>CURRENCY</cmdty:space>
        <cmdty:id>USD</cmdty:id>
      </trn:currency>
      <trn:date-posted>
        <ts:date>2026-10-03 10:59:00 +0000</ts:date>
      </trn:date-posted>
      <trn:date-entered>
        <ts:date>2026-10-04 15:30:00 +0000</ts:date>
      </trn:date-entered>
      <trn:description>Corner Café &amp; &lt;Bakery&gt;</trn:description>
      <trn:slots>
        <slot>
          <slot:key>date-posted</slot:key>
          <slot:value type="gdate">
            <gdate>2026-10-03</gdate>
          </slot:value>
        </slot>
      </trn:slots>
      <trn:splits>
        <trn:split>
          <split:id type="guid">e0000000000000000000000000000002</split:id>
          <split:memo>Lunch</split:memo>
          <split:reconciled-state>n</split:reconciled-state>
          <split:value>1250/100</split:value>
          <split:quantity>1250/100</split:quantity>
          <split:account type="guid">a0000000000000000000000000000007</split:account>
        </trn:split>
        <trn:split>
          <split:id type="guid">e0000000000000000000000000000003</split:id>
          <split:reconciled-state>n</split:reconciled-state>
          <split:value>-1250/100</split:value>
          <split:quantity>-1250/100</split:quantity>
          <split:account type="guid">a0000000000000000000000000000004</split:account>
        </trn:split>
      </trn:splits>
    </gnc:transaction>

    """

    func testAppendInsertsGnuCashFormattedTransactionBeforeTemplatesAndUpdatesTheCount() throws {
        let original = try xml()
        let result = try appendingTransactions([lunch()], toBookXML: original, book: try book(), enteredAt: entered,
                                               makeGUID: guids())
        let insertion = try XCTUnwrap(original.range(of: "<gnc:template-transactions>")).lowerBound
        var expected = original
        expected.insert(contentsOf: expectedLunchXML, at: insertion)
        expected = expected.replacingOccurrences(of: "<gnc:count-data cd:type=\"transaction\">2</gnc:count-data>",
                                                 with: "<gnc:count-data cd:type=\"transaction\">3</gnc:count-data>")
        XCTAssertEqual(result, expected)
    }

    func testAppendedTransactionsReadBackInOrder() throws {
        let numbered = NewGnuCashTransaction(date: date(2026, 10, 2), description: "Synthetic Fund Dividend", num: "1002", splits: [
            NewGnuCashSplit(accountName: "Assets:Checking", amount: dec("3.4")),
            NewGnuCashSplit(accountName: "Dividends", amount: dec("-3.4")),
        ])
        let result = try appendingTransactions([lunch(), numbered], toBookXML: try xml(), book: try book(),
                                               enteredAt: entered, makeGUID: guids())
        let reread = try parseGnuCashBook(Data(result.utf8))
        XCTAssertEqual(reread.transactions.count, 4)
        XCTAssertEqual(reread.transactions[2].description, "Corner Café & <Bakery>")
        XCTAssertEqual(reread.transactions[2].datePosted, date(2026, 10, 3))
        XCTAssertEqual(reread.transactions[2].dateEntered, entered)
        XCTAssertEqual(reread.transactions[2].splits.map(\.value), [dec("12.5"), dec("-12.5")])
        XCTAssertEqual(reread.transactions[3].num, "1002")
        XCTAssertEqual(reread.transactions[3].splits.map(\.value), [dec("3.4"), dec("-3.4")])
        XCTAssertTrue(result.contains("<split:value>340/100</split:value>"))
        XCTAssertTrue(result.contains("<gnc:count-data cd:type=\"transaction\">4</gnc:count-data>"))
    }

    func testFirstTransactionAddsTheCountAfterTheAccountCount() throws {
        var original = try xml()
        let first = try XCTUnwrap(original.range(of: "<gnc:transaction version"))
        let last = try XCTUnwrap(original.range(of: "<gnc:template-transactions>"))
        original.removeSubrange(first.lowerBound..<last.lowerBound)
        original = original.replacingOccurrences(of: "<gnc:count-data cd:type=\"transaction\">2</gnc:count-data>\n", with: "")
        let empty = try parseGnuCashBook(Data(original.utf8))
        XCTAssertEqual(empty.transactions, [])
        let result = try appendingTransactions([lunch()], toBookXML: original, book: empty, enteredAt: entered, makeGUID: guids())
        XCTAssertTrue(result.contains("<gnc:count-data cd:type=\"account\">8</gnc:count-data>\n<gnc:count-data cd:type=\"transaction\">1</gnc:count-data>\n<gnc:commodity"))
        XCTAssertEqual(try parseGnuCashBook(Data(result.utf8)).transactions.count, 1)
    }

    func testInvalidTransactionsAreRejected() throws {
        let book = try book()
        let xml = try xml()
        func attempt(_ splits: [NewGnuCashSplit]) throws -> String {
            try appendingTransactions([NewGnuCashTransaction(date: date(2026, 10, 3), description: "Test", splits: splits)],
                                      toBookXML: xml, book: book, enteredAt: entered, makeGUID: guids())
        }
        assertGnuCashError(.unknownAccount("Expenses:Travel"), try attempt([
            NewGnuCashSplit(accountName: "Expenses:Travel", amount: 1), NewGnuCashSplit(accountName: "Credit Card", amount: -1)]))
        assertGnuCashError(.placeholderAccount("Expenses"), try attempt([
            NewGnuCashSplit(accountName: "Expenses", amount: 1), NewGnuCashSplit(accountName: "Credit Card", amount: -1)]))
        assertGnuCashError(.needsTwoSplits, try attempt([NewGnuCashSplit(accountName: "Credit Card", amount: 0)]))
        assertGnuCashError(.unbalanced(dec("0.01")), try attempt([
            NewGnuCashSplit(accountName: "Expenses:Dining", amount: dec("12.51")),
            NewGnuCashSplit(accountName: "Credit Card", amount: dec("-12.50"))]))
        assertGnuCashError(.tooPrecise(account: "Expenses:Dining", amount: dec("1.005")), try attempt([
            NewGnuCashSplit(accountName: "Expenses:Dining", amount: dec("1.005")),
            NewGnuCashSplit(accountName: "Credit Card", amount: dec("-1.005"))]))
        assertGnuCashError(.unknownAccount(""), try attempt([
            NewGnuCashSplit(accountName: "", amount: 1), NewGnuCashSplit(accountName: "Credit Card", amount: -1)]))
    }

    func testAccountsInDifferentCurrenciesAreRejected() throws {
        let euroXML = try xml().replacingOccurrences(of: """
          <act:name>Dining</act:name>
          <act:id type="guid">a0000000000000000000000000000007</act:id>
          <act:type>EXPENSE</act:type>
          <act:commodity>
            <cmdty:space>CURRENCY</cmdty:space>
            <cmdty:id>USD</cmdty:id>
        """, with: """
          <act:name>Dining</act:name>
          <act:id type="guid">a0000000000000000000000000000007</act:id>
          <act:type>EXPENSE</act:type>
          <act:commodity>
            <cmdty:space>CURRENCY</cmdty:space>
            <cmdty:id>EUR</cmdty:id>
        """)
        XCTAssertNotEqual(euroXML, try xml())
        let euroBook = try parseGnuCashBook(Data(euroXML.utf8))
        assertGnuCashError(.mixedCurrencies, try appendingTransactions([lunch()], toBookXML: euroXML, book: euroBook,
                                                                       enteredAt: entered, makeGUID: guids()))
    }

    // MARK: - Book files

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("gnucash-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func bookFile(compressed: Bool) throws -> URL {
        let url = directory.appendingPathComponent("Household.gnucash")
        try fixture("gnucash-book.synthetic", compressed ? "gnucash" : "xml").write(to: url)
        return url
    }

    func testStoreAppendsKeepsCompressionAndBacksUp() throws {
        for compressed in [true, false] {
            let url = try bookFile(compressed: compressed)
            let original = try Data(contentsOf: url)
            let backups = directory.appendingPathComponent("Backups-\(compressed)")
            let store = GnuCashBookStore(url: url)
            let added = try store.append([lunch()], backupDirectory: backups, now: entered, makeGUID: guids())
            XCTAssertEqual(added, ["e0000000000000000000000000000001"])

            let saved = try Data(contentsOf: url)
            XCTAssertEqual(Gzip.isCompressed(saved), compressed)
            XCTAssertEqual(try store.load().transactions.last?.guid, "e0000000000000000000000000000001")
            let backupFiles = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
            XCTAssertEqual(backupFiles.count, 1)
            XCTAssertEqual(try Data(contentsOf: backupFiles[0]), original)
            XCTAssertTrue(backupFiles[0].lastPathComponent.hasPrefix("Household-backup-"))
            XCTAssertEqual(backupFiles[0].pathExtension, "gnucash")
        }
    }

    func testStoreRefusesWhileGnuCashHasTheBookOpen() throws {
        let url = try bookFile(compressed: true)
        let original = try Data(contentsOf: url)
        let store = GnuCashBookStore(url: url)
        XCTAssertEqual(store.lockURL.lastPathComponent, "Household.gnucash.LCK")
        try Data().write(to: store.lockURL)
        let backups = directory.appendingPathComponent("Backups")
        assertGnuCashError(.bookOpenInGnuCash("Household.gnucash"),
                           try store.append([lunch()], backupDirectory: backups, now: entered, makeGUID: guids()))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backups.path))
        XCTAssertEqual(try store.load().transactions.count, 2)
    }

    func testInvalidAppendLeavesTheBookAndBackupsUntouched() throws {
        let url = try bookFile(compressed: false)
        let original = try Data(contentsOf: url)
        let backups = directory.appendingPathComponent("Backups")
        let bad = NewGnuCashTransaction(date: date(2026, 10, 3), description: "Test", splits: [
            NewGnuCashSplit(accountName: "Expenses:Travel", amount: 1), NewGnuCashSplit(accountName: "Credit Card", amount: -1)])
        assertGnuCashError(.unknownAccount("Expenses:Travel"),
                           try GnuCashBookStore(url: url).append([bad], backupDirectory: backups, now: entered, makeGUID: guids()))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backups.path))
    }
}

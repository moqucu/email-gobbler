import Foundation
import XCTest
import EmailGobblerCore
import GnuCashBook
import SpendingEmails
@testable import EmailGobblerService

final class SpendingRunTests: XCTestCase {
    private static let bookURL = URL(fileURLWithPath: "/tmp/Household.gnucash")

    private func source(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "eml", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> CalendarDate { try! CalendarDate(year: y, month: m, day: d) }
    private func dec(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    private func account(_ guid: String, _ name: String, _ type: String) -> GnuCashAccount {
        GnuCashAccount(guid: guid, name: name.split(separator: ":").last.map(String.init) ?? "Root Account", fullName: name, type: type,
                       commodity: GnuCashCommodity(space: "CURRENCY", id: "USD"), commoditySCU: 100, parentGUID: nil,
                       isPlaceholder: false)
    }

    private func book() -> GnuCashBook {
        GnuCashBook(bookGUID: "b", accounts: [
            account("root", "", "ROOT"),
            account("card", "Liabilities:Example Card", "CREDIT"),
            account("paypal", "Assets:PayPal", "ASSET"),
            account("bank", "Assets:Checking", "BANK"),
            account("hold", "Expenses:Uncategorized", "EXPENSE"),
        ], transactions: [])
    }

    private func amex() -> AmexPurchasesUseCase {
        AmexPurchasesUseCase(bookURL: Self.bookURL, amexAccount: "Liabilities:Example Card", holdingAccount: "Expenses:Uncategorized")
    }

    private func payPal() -> PayPalPaymentsUseCase {
        PayPalPaymentsUseCase(bookURL: Self.bookURL, accounts: PayPalAccounts(payPal: "Assets:PayPal", bankFunding: "Assets:Checking",
                                                                               cardFunding: "Liabilities:Example Card"),
                              holdingAccount: "Expenses:Uncategorized")
    }

    // MARK: - Use cases

    func testAmexUseCaseSummarizesAndPlansThePurchase() throws {
        let html = try MailDecoder.html(from: try source("amex-purchase.synthetic"))
        let useCase = amex()
        XCTAssertEqual(useCase.mailQuery, AmexPurchasesUseCase.defaultQuery)
        XCTAssertEqual(useCase.targets, [])
        XCTAssertEqual(try useCase.summarize(html: html), ["Merchant: EXAMPLE PROPANE CO", "Amount: $42.17", "Date: 3/12/2026"])
        let plan = try useCase.planBook(html: html, book: book())
        XCTAssertEqual(plan.transactions.map(\.description), ["Example Propane Co"])
        XCTAssertEqual(plan.notes, ["New merchant \"Example Propane Co\" booked to Expenses:Uncategorized"])
    }

    func testPayPalUseCaseSummarizesAndPlansBothTransactions() throws {
        let html = try MailDecoder.html(from: try source("paypal-receipt.synthetic"))
        let useCase = payPal()
        XCTAssertEqual(useCase.mailQuery, PayPalPaymentsUseCase.defaultQuery)
        XCTAssertEqual(try useCase.summarize(html: html),
                       ["Merchant: Example Streaming", "Amount: $15.49", "Date: 3/12/2026", "Funding: 1 source"])
        XCTAssertEqual(try useCase.planBook(html: html, book: book()).transactions.map(\.description),
                       ["Example Streaming", "PayPal - Collection"])
    }

    func testOnlyNotApplicableEmailsStayInTheInbox() {
        XCTAssertTrue(SpendingEmailError.notApplicable("Not a receipt").leavesEmailInInbox)
        XCTAssertFalse(SpendingEmailError.missingField("Transaction ID").leavesEmailInInbox)
        XCTAssertFalse(SpendingEmailError.unsupportedFunding("Venmo").leavesEmailInInbox)
    }

    // MARK: - Runner

    private final class FakeBookClient: AutomationClient {
        var messages: [MailMessageRef] = []
        var sources: [Int32: Data] = [:]
        var book: GnuCashBook
        var failAppend = false
        var calls: [String] = []
        var appended: [NewGnuCashTransaction] = []

        init(book: GnuCashBook) { self.book = book }

        func listMessages(_ query: MailQuery) throws -> [MailMessageRef] { calls.append("list"); return messages }
        func fetchMessage(_ ref: MailMessageRef) throws -> FetchedMailMessage {
            calls.append("fetch \(ref.id)")
            return FetchedMailMessage(source: sources[ref.id]!, id: ref.id, accountID: ref.accountID, rfcMessageID: ref.rfcMessageID)
        }
        func readSheet(_ target: SheetTarget) throws -> SheetSnapshot { XCTFail("no sheets"); return SheetSnapshot(rows: []) }
        func writeSheet(_ plan: TargetPlan, plannedFrom: SheetSnapshot, backup: URL) throws { XCTFail("no sheets") }
        func consume(_ message: FetchedMailMessage) throws { calls.append("consume \(message.id)") }

        func loadBook(_ url: URL) throws -> GnuCashBook {
            calls.append("load \(url.lastPathComponent)")
            return book
        }

        func appendToBook(_ url: URL, _ transactions: [NewGnuCashTransaction], backup: URL) throws {
            calls.append("append \(transactions.count)")
            struct Locked: Error, CustomStringConvertible { var description: String { "Close the book in GnuCash" } }
            if failAppend { throw Locked() }
            try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: backup)
            appended += transactions
        }
    }

    private var base: URL!
    private var tick = 0

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("spending-run-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func environment(_ client: FakeBookClient, retention: Int = 30) -> RunEnvironment {
        RunEnvironment(client: client, backupBase: base, retention: retention, now: {
            self.tick += 1
            return Date(timeIntervalSince1970: 1_790_000_000 + Double(self.tick))
        })
    }

    private func ref(_ id: Int32) -> MailMessageRef {
        MailMessageRef(id: id, accountID: "ICLOUD", rfcMessageID: "<\(id)@example.invalid>", ageOffset: -Int(id))
    }

    func testBookUseCasesAppendBeforeArchivingAndPruneBookBackups() throws {
        let client = FakeBookClient(book: book())
        client.messages = [ref(7), ref(8)]
        client.sources = [7: try source("paypal-receipt.synthetic"), 8: try source("paypal-receipt.synthetic")]
        let result = runUseCase(ConfiguredUseCase(id: .payPalPayments, useCase: payPal()), environment: environment(client, retention: 1))
        XCTAssertNil(result.error)
        XCTAssertEqual(result.messagesProcessed, 2)
        XCTAssertEqual(result.rowsWritten, 4)
        XCTAssertEqual(client.calls, ["list", "fetch 7", "load Household.gnucash", "append 2", "consume 7",
                                      "fetch 8", "load Household.gnucash", "append 2", "consume 8"])
        let backups = try FileManager.default.contentsOfDirectory(atPath: base.appendingPathComponent("Backups/paypal-payments").path)
        XCTAssertEqual(backups.count, 1)
        XCTAssertTrue(backups[0].hasPrefix("Household-backup-") && backups[0].hasSuffix(".gnucash"), backups[0])
    }

    func testEmailsThatAreNotPurchasesAreSkippedAndLeftInTheInbox() throws {
        let client = FakeBookClient(book: book())
        let statement = String(decoding: try source("amex-purchase.synthetic"), as: UTF8.self)
            .replacingOccurrences(of: "$42.17*", with: "View your statement")
        client.messages = [ref(7), ref(8)]
        client.sources = [7: Data(statement.utf8), 8: try source("amex-purchase.synthetic")]
        let result = runUseCase(ConfiguredUseCase(id: .amexPurchases, useCase: amex()), environment: environment(client))
        XCTAssertEqual(result, UseCaseRunResult(id: .amexPurchases, messagesFound: 2, messagesProcessed: 1, rowsWritten: 1, error: nil,
                                                lastProcessedAt: Date(timeIntervalSince1970: 1_790_000_002)))
        XCTAssertEqual(client.calls, ["list", "fetch 7", "fetch 8", "load Household.gnucash", "append 1", "consume 8"])
    }

    func testAFailedAppendKeepsTheEmail() throws {
        let client = FakeBookClient(book: book())
        client.failAppend = true
        client.messages = [ref(7)]
        client.sources = [7: try source("amex-purchase.synthetic")]
        let result = runUseCase(ConfiguredUseCase(id: .amexPurchases, useCase: amex()), environment: environment(client))
        XCTAssertEqual(result.error, "Close the book in GnuCash")
        XCTAssertEqual(client.calls, ["list", "fetch 7", "load Household.gnucash", "append 1"])
    }

    func testUseCaseNames() {
        XCTAssertEqual(UseCaseID.amexPurchases.rawValue, "amex-purchases")
        XCTAssertEqual(UseCaseID.payPalPayments.rawValue, "paypal-payments")
        XCTAssertEqual(UseCaseID.amexPurchases.displayName, "AmEx purchases")
        XCTAssertEqual(UseCaseID.payPalPayments.displayName, "PayPal payments")
    }
}

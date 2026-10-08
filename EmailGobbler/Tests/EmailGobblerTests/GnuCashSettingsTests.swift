import Foundation
import XCTest
import EmailGobblerCore
import GnuCashBook
@testable import EmailGobblerService

final class GnuCashSettingsTests: XCTestCase {
    private func settings(bookPath: String?) -> AppSettings {
        AppSettings(intervalMinutes: 30, backupRetention: 30, grades: GradesSettings(enabled: false, routes: []),
                    dividends: DividendsSettings(enabled: false, workbookPath: nil, sheetName: "Sheet 1"),
                    gnuCash: GnuCashSettings(bookPath: bookPath))
    }

    private func syntheticBook() throws -> GnuCashBook {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "gnucash-book.synthetic", withExtension: "xml", subdirectory: "Fixtures"))
        return try parseGnuCashBook(Data(contentsOf: url))
    }

    func testSettingsWithoutAGnuCashBookStillLoad() throws {
        let json = """
        {"version":1,"intervalMinutes":30,"backupRetention":30,
         "grades":{"enabled":false,"routes":[]},
         "dividends":{"enabled":false,"sheetName":"Sheet 1"}}
        """
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.gnuCash, GnuCashSettings(bookPath: nil))
        XCTAssertEqual(AppSettings.standard.gnuCash, GnuCashSettings(bookPath: nil))
    }

    func testGnuCashBookPathRoundTrips() throws {
        let original = settings(bookPath: "/tmp/Household.gnucash")
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(original)), original)
    }

    func testBlankBookPathNeedsAttention() {
        XCTAssertEqual(settings(bookPath: nil).validate(), [])
        XCTAssertEqual(settings(bookPath: "/tmp/Household.gnucash").validate(), [])
        XCTAssertEqual(settings(bookPath: "  ").validate(),
                       [SettingsIssue(field: "gnuCash.bookPath", message: "Choose a GnuCash book")])
    }

    func testPreflightOpensTheChosenBook() throws {
        let book = try syntheticBook()
        var opened: [String] = []
        let issues = preflightIssues(settings(bookPath: "/tmp/Household.gnucash"), readSheet: { _ in
            XCTFail("no sheets are enabled")
            return SheetSnapshot(rows: [])
        }, loadBook: { url in
            opened.append(url.path)
            return book
        })
        XCTAssertEqual(issues, [])
        XCTAssertEqual(opened, ["/tmp/Household.gnucash"])
    }

    func testPreflightReportsAnUnreadableBookAndSkipsAnUnsetOne() {
        let issues = preflightIssues(settings(bookPath: "/tmp/Notes.gnucash"), readSheet: { _ in SheetSnapshot(rows: []) },
                                     loadBook: { _ in throw GnuCashError.notAGnuCashBook })
        XCTAssertEqual(issues, [SettingsIssue(field: "gnuCash.bookPath",
                                              message: "Notes.gnucash: The file is not a GnuCash XML book")])
        XCTAssertEqual(preflightIssues(settings(bookPath: nil), readSheet: { _ in SheetSnapshot(rows: []) },
                                       loadBook: { _ in XCTFail("should not open"); throw GnuCashError.notAGnuCashBook }), [])
    }

    func testBookSummaryCountsAccountsCurrenciesAndTransactions() throws {
        XCTAssertEqual(gnuCashBookSummary(try syntheticBook(), fileName: "Household.gnucash"),
                       "Household.gnucash: 7 accounts, 5 can hold transactions, in USD; 2 transactions")
    }

    // MARK: - Spending bookings

    private func spending(amex: Bool = true, payPal: Bool = true, verizon: Bool = true) -> AppSettings {
        AppSettings(intervalMinutes: 30, backupRetention: 30, grades: GradesSettings(enabled: false, routes: []),
                    dividends: DividendsSettings(enabled: false, workbookPath: nil, sheetName: "Sheet 1"),
                    gnuCash: GnuCashSettings(bookPath: "/tmp/Household.gnucash", holdingAccount: "Expenses:Uncategorized",
                                             amex: AmexBookingSettings(enabled: amex, account: "Liabilities:Example Card"),
                                             payPal: PayPalBookingSettings(enabled: payPal, account: "Assets:PayPal",
                                                                           bankFundingAccount: "Assets:Checking",
                                                                           cardFundingAccount: "Liabilities:Example Card"),
                                             verizon: VerizonBookingSettings(enabled: verizon, account: "Assets:Checking")))
    }

    private func spendingBook(placeholder: String? = nil) -> GnuCashBook {
        let names = [("Liabilities:Example Card", "CREDIT"), ("Assets:PayPal", "ASSET"), ("Assets:Checking", "BANK"),
                     ("Expenses:Uncategorized", "EXPENSE")]
        return GnuCashBook(bookGUID: "b", accounts: names.map { name, type in
            GnuCashAccount(guid: name, name: String(name.split(separator: ":").last!), fullName: name, type: type,
                           commodity: GnuCashCommodity(space: "CURRENCY", id: "USD"), commoditySCU: 100, parentGUID: nil,
                           isPlaceholder: name == placeholder)
        }, transactions: [])
    }

    func testSpendingSettingsDefaultOffAndOlderBookSettingsStillLoad() throws {
        let json = #"{"bookPath":"/tmp/Household.gnucash"}"#
        let decoded = try JSONDecoder().decode(GnuCashSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, GnuCashSettings(bookPath: "/tmp/Household.gnucash"))
        XCTAssertFalse(decoded.amex.enabled)
        XCTAssertFalse(decoded.payPal.enabled)
        XCTAssertNil(decoded.holdingAccount)
        XCTAssertFalse(decoded.verizon.enabled)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(spending())), spending())
    }

    func testEnabledBookingsNeedABookAndTheirAccounts() {
        XCTAssertEqual(spending().validate(), [])
        var missing = spending()
        missing.gnuCash = GnuCashSettings(bookPath: nil, holdingAccount: " ",
                                          amex: AmexBookingSettings(enabled: true, account: nil),
                                          payPal: PayPalBookingSettings(enabled: true, account: nil, bankFundingAccount: "",
                                                                        cardFundingAccount: nil),
                                          verizon: VerizonBookingSettings(enabled: true, account: nil))
        XCTAssertEqual(missing.validate(), [
            SettingsIssue(field: "gnuCash.bookPath", message: "Choose a GnuCash book"),
            SettingsIssue(field: "gnuCash.holdingAccount", message: "Choose an account for new merchants"),
            SettingsIssue(field: "gnuCash.amex.account", message: "Choose the American Express account"),
            SettingsIssue(field: "gnuCash.payPal.account", message: "Choose the PayPal account"),
            SettingsIssue(field: "gnuCash.payPal.bankFundingAccount", message: "Choose the bank account that funds PayPal"),
            SettingsIssue(field: "gnuCash.payPal.cardFundingAccount", message: "Choose the card account that funds PayPal"),
            SettingsIssue(field: "gnuCash.verizon.account", message: "Choose the account that pays the Verizon bill"),
        ])
        missing.gnuCash.amex.enabled = false
        missing.gnuCash.payPal.enabled = false
        XCTAssertEqual(missing.validate().map(\.field), ["gnuCash.bookPath", "gnuCash.holdingAccount", "gnuCash.verizon.account"])
        missing.gnuCash.verizon.enabled = false
        XCTAssertEqual(missing.validate(), [])
    }

    func testPreflightChecksTheChosenAccountsExistAndHoldTransactions() {
        XCTAssertEqual(preflightIssues(spending(), readSheet: { _ in SheetSnapshot(rows: []) }, loadBook: { _ in self.spendingBook() }), [])
        var renamed = spending()
        renamed.gnuCash.payPal.account = "Assets:Missing"
        renamed.gnuCash.verizon.account = "Assets:Old Checking"
        XCTAssertEqual(preflightIssues(renamed, readSheet: { _ in SheetSnapshot(rows: []) },
                                       loadBook: { _ in self.spendingBook(placeholder: "Expenses:Uncategorized") }), [
            SettingsIssue(field: "gnuCash.holdingAccount", message: "Expenses:Uncategorized is a placeholder and can't hold transactions"),
            SettingsIssue(field: "gnuCash.payPal.account", message: "Assets:Missing is not in Household.gnucash"),
            SettingsIssue(field: "gnuCash.verizon.account", message: "Assets:Old Checking is not in Household.gnucash"),
        ])
    }

    func testPreflightRefusesAccountsOfTheWrongKind() {
        var swapped = spending()
        swapped.gnuCash.verizon.account = "Expenses:Uncategorized"
        swapped.gnuCash.holdingAccount = "Assets:Checking"
        swapped.gnuCash.amex.account = "Assets:PayPal"
        XCTAssertEqual(preflightIssues(swapped, readSheet: { _ in SheetSnapshot(rows: []) }, loadBook: { _ in self.spendingBook() }), [
            SettingsIssue(field: "gnuCash.holdingAccount", message: "Assets:Checking is a bank account; choose an expense account"),
            SettingsIssue(field: "gnuCash.amex.account",
                          message: "Assets:PayPal is an asset account; choose a credit card or liability account"),
            SettingsIssue(field: "gnuCash.verizon.account",
                          message: "Expenses:Uncategorized is an expense account; choose a bank, asset, or card account"),
        ])
    }

    func testEnabledBookingsBecomeUseCases() {
        XCTAssertEqual(spending().configuredUseCases().map(\.id), [.amexPurchases, .payPalPayments, .verizonBills])
        XCTAssertEqual(spending(amex: false, verizon: false).configuredUseCases().map(\.id), [.payPalPayments])
        XCTAssertEqual(spending(amex: false, payPal: false).configuredUseCases().map(\.id), [.verizonBills])
        XCTAssertEqual(spending(amex: false, payPal: false, verizon: false).configuredUseCases().map(\.id), [])
    }

    func testPostableAccountNamesForPickers() {
        XCTAssertEqual(postableAccountNames(spendingBook(placeholder: "Assets:Checking")),
                       ["Assets:PayPal", "Expenses:Uncategorized", "Liabilities:Example Card"])
        let book = spendingBook()
        XCTAssertEqual(postableAccountNames(book, for: .expense), ["Expenses:Uncategorized"])
        XCTAssertEqual(postableAccountNames(book, for: .card), ["Liabilities:Example Card"])
        XCTAssertEqual(postableAccountNames(book, for: .bank), ["Assets:Checking", "Assets:PayPal"])
        XCTAssertEqual(postableAccountNames(book, for: .billPayment), ["Assets:Checking", "Assets:PayPal", "Liabilities:Example Card"])
        XCTAssertEqual(postableAccountNames(book, for: .wallet), ["Assets:Checking", "Assets:PayPal"])
    }
}

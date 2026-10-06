import Foundation
import XCTest
import EmailGobblerCore
import GnuCashBook
@testable import SpendingEmails

// Fixtures are anonymized copies of one real AmEx alert and one real PayPal
// receipt. Other inputs are constructed variants, not observed email formats.
final class SpendingEmailsTests: XCTestCase {
    private func html(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "eml", subdirectory: "Fixtures"))
        return try MailDecoder.html(from: Data(contentsOf: url))
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> CalendarDate { try! CalendarDate(year: y, month: m, day: d) }
    private func dec(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    private func assertSpendingError<T>(_ expected: SpendingEmailError, _ expression: @autoclosure () throws -> T,
                                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? SpendingEmailError, expected, file: file, line: line)
        }
    }

    // MARK: - AmEx alerts

    func testAmexAlertFixtureIsParsed() throws {
        XCTAssertEqual(try parseAmexPurchaseAlert(html: try html("amex-purchase.synthetic")),
                       AmexPurchase(merchant: "EXAMPLE PROPANE CO", amount: dec("42.17"), date: date(2026, 3, 12), accountEnding: "100042"))
    }

    func testAmexAmountsWithThousandsAndWithoutAsterisk() throws {
        let variant = try html("amex-purchase.synthetic").replacingOccurrences(of: "$42.17*", with: "$1,234.56")
        XCTAssertEqual(try parseAmexPurchaseAlert(html: variant).amount, dec("1234.56"))
    }

    func testAmexEmailsWithoutAPurchaseAreNotApplicable() throws {
        let statement = try html("amex-purchase.synthetic").replacingOccurrences(of: "$42.17*", with: "View your statement")
        assertSpendingError(.notApplicable("Not an American Express purchase alert"), try parseAmexPurchaseAlert(html: statement))
        let badDate = try html("amex-purchase.synthetic").replacingOccurrences(of: "Thu, Mar 12, 2026", with: "Thu, Feb 30, 2026")
        assertSpendingError(.invalidDate("Thu, Feb 30, 2026"), try parseAmexPurchaseAlert(html: badDate))
    }

    // MARK: - PayPal receipts

    func testPayPalReceiptFixtureIsParsed() throws {
        XCTAssertEqual(try parsePayPalReceipt(html: try html("paypal-receipt.synthetic")), PayPalPayment(
            merchant: "Example Streaming", amount: dec("15.49"), currency: "USD", date: date(2026, 3, 12),
            transactionID: "SYNTH0000TXN00042",
            funding: [PayPalFunding(source: "WELLS FARGO BANK NA Checking ••0042", amount: dec("15.49"))]))
    }

    func testPayPalEmailsThatAreNotPaymentsOrNotUSDAreRejected() throws {
        let received = try html("paypal-receipt.synthetic").replacingOccurrences(of: "You paid $15.49\u{00A0}USD to Example Streaming",
                                                                                 with: "You received $15.49\u{00A0}USD from Example Streaming")
        assertSpendingError(.notApplicable("Not a PayPal payment receipt"), try parsePayPalReceipt(html: received))
        let euro = try html("paypal-receipt.synthetic").replacingOccurrences(of: "You paid $15.49\u{00A0}USD", with: "You paid €15.49\u{00A0}EUR")
        assertSpendingError(.unsupportedCurrency("EUR"), try parsePayPalReceipt(html: euro))
        let noID = try html("paypal-receipt.synthetic").replacingOccurrences(of: "Transaction ID", with: "Reference")
        assertSpendingError(.missingField("Transaction ID"), try parsePayPalReceipt(html: noID))
        let noFunding = try html("paypal-receipt.synthetic").replacingOccurrences(of: "Paid Example Streaming with", with: "Details")
        assertSpendingError(.missingField("payment method"), try parsePayPalReceipt(html: noFunding))
    }

    // MARK: - Booking

    private func account(_ guid: String, _ name: String, _ type: String, placeholder: Bool = false) -> GnuCashAccount {
        GnuCashAccount(guid: guid, name: name.split(separator: ":").last.map(String.init) ?? "Root Account", fullName: name, type: type,
                       commodity: GnuCashCommodity(space: "CURRENCY", id: "USD"), commoditySCU: 100, parentGUID: nil,
                       isPlaceholder: placeholder)
    }

    private func booking(_ guid: String, _ day: CalendarDate, _ description: String, num: String? = nil,
                         _ splits: [(String, String)]) -> GnuCashTransaction {
        GnuCashTransaction(guid: guid, currency: GnuCashCommodity(space: "CURRENCY", id: "USD"), num: num, datePosted: day,
                           dateEntered: Date(timeIntervalSince1970: 0), description: description,
                           splits: splits.enumerated().map { index, split in
                               GnuCashSplit(guid: "\(guid)-\(index)", accountGUID: split.0, value: dec(split.1),
                                            quantity: dec(split.1), memo: nil, reconciledState: "n")
                           })
    }

    /// A synthetic household book shaped like a real one: card and PayPal history to learn from.
    private func book(extra: [GnuCashTransaction] = []) -> GnuCashBook {
        GnuCashBook(bookGUID: "b", accounts: [
            account("root", "", "ROOT"),
            account("amex", "Liabilities:Example Card", "CREDIT"),
            account("paypal", "Assets:PayPal", "ASSET"),
            account("bank", "Assets:Checking", "BANK"),
            account("gas", "Expenses:Utilities:Gas", "EXPENSE"),
            account("streaming", "Expenses:Streaming", "EXPENSE"),
            account("hold", "Expenses:Uncategorized", "EXPENSE"),
            account("exp", "Expenses", "EXPENSE", placeholder: true),
        ], transactions: [
            booking("t1", date(2026, 1, 9), "Example Propane Co", [("gas", "38.00"), ("amex", "-38.00")]),
            booking("t2", date(2026, 2, 9), "Example Propane Co", [("gas", "40.00"), ("amex", "-40.00")]),
            booking("t3", date(2026, 2, 12), "Example Streaming", [("streaming", "15.49"), ("paypal", "-15.49")]),
            booking("t4", date(2026, 2, 12), "PayPal - Collection", [("paypal", "15.49"), ("bank", "-15.49")]),
        ] + extra)
    }

    private let payPalAccounts = PayPalAccounts(payPal: "Assets:PayPal", bankFunding: "Assets:Checking",
                                                cardFunding: "Liabilities:Example Card")

    private func payment(funding source: String = "WELLS FARGO BANK NA Checking ••0042") -> PayPalPayment {
        PayPalPayment(merchant: "Example Streaming", amount: dec("15.49"), currency: "USD", date: date(2026, 3, 12),
                      transactionID: "SYNTH0000TXN00042", funding: [PayPalFunding(source: source, amount: dec("15.49"))])
    }

    func testAmexPurchaseLearnsDescriptionAndExpenseAccountFromTheLatestBooking() throws {
        let purchase = AmexPurchase(merchant: "EXAMPLE PROPANE CO", amount: dec("42.17"), date: date(2026, 3, 12), accountEnding: "100042")
        let plan = try planAmexPurchase(purchase, book: book(), amexAccount: "Liabilities:Example Card",
                                        holdingAccount: "Expenses:Uncategorized")
        XCTAssertEqual(plan, SpendingPlan(transactions: [
            NewGnuCashTransaction(date: date(2026, 3, 12), description: "Example Propane Co", splits: [
                NewGnuCashSplit(accountName: "Expenses:Utilities:Gas", amount: dec("42.17")),
                NewGnuCashSplit(accountName: "Liabilities:Example Card", amount: dec("-42.17")),
            ]),
        ], notes: []))
    }

    func testNewMerchantGoesToTheHoldingAccountWithAReadableName() throws {
        let purchase = AmexPurchase(merchant: "NEW HARDWARE STORE #12", amount: dec("9.99"), date: date(2026, 3, 12), accountEnding: nil)
        let plan = try planAmexPurchase(purchase, book: book(), amexAccount: "Liabilities:Example Card",
                                        holdingAccount: "Expenses:Uncategorized")
        XCTAssertEqual(plan.transactions.first?.description, "New Hardware Store #12")
        XCTAssertEqual(plan.transactions.first?.splits.first?.accountName, "Expenses:Uncategorized")
        XCTAssertEqual(plan.notes, ["New merchant \"New Hardware Store #12\" booked to Expenses:Uncategorized"])
    }

    func testSameAmountOnTheCardWithinThreeDaysCountsAsBooked() throws {
        let purchase = AmexPurchase(merchant: "EXAMPLE PROPANE CO", amount: dec("42.17"), date: date(2026, 3, 12), accountEnding: nil)
        for (day, booked) in [(9, true), (15, true), (8, false), (16, false)] {
            let existing = booking("pre", date(2026, 3, day), "Another Propane", [("gas", "42.17"), ("amex", "-42.17")])
            let plan = try planAmexPurchase(purchase, book: book(extra: [existing]), amexAccount: "Liabilities:Example Card",
                                            holdingAccount: "Expenses:Uncategorized")
            XCTAssertEqual(plan.transactions.isEmpty, booked, "existing booking on day \(day)")
            if booked {
                XCTAssertEqual(plan.notes, ["Already booked: Another Propane $42.17 on 3/\(day)/2026"])
            }
        }
    }

    func testPayPalPaymentBooksThePurchaseAndTheBankCollection() throws {
        let plan = try planPayPalPayment(payment(), book: book(), accounts: payPalAccounts, holdingAccount: "Expenses:Uncategorized")
        XCTAssertEqual(plan, SpendingPlan(transactions: [
            NewGnuCashTransaction(date: date(2026, 3, 12), description: "Example Streaming", num: "SYNTH0000TXN00042", splits: [
                NewGnuCashSplit(accountName: "Expenses:Streaming", amount: dec("15.49")),
                NewGnuCashSplit(accountName: "Assets:PayPal", amount: dec("-15.49")),
            ]),
            NewGnuCashTransaction(date: date(2026, 3, 12), description: "PayPal - Collection", num: "SYNTH0000TXN00042", splits: [
                NewGnuCashSplit(accountName: "Assets:PayPal", amount: dec("15.49")),
                NewGnuCashSplit(accountName: "Assets:Checking", amount: dec("-15.49")),
            ]),
        ], notes: []))
    }

    func testPayPalCardFundingIsAnAmExCollectionAndBalanceNeedsNone() throws {
        let card = try planPayPalPayment(payment(funding: "American Express ••1002"), book: book(), accounts: payPalAccounts,
                                         holdingAccount: "Expenses:Uncategorized")
        XCTAssertEqual(card.transactions.last, NewGnuCashTransaction(
            date: date(2026, 3, 12), description: "AmEx - Collection", num: "SYNTH0000TXN00042", splits: [
                NewGnuCashSplit(accountName: "Assets:PayPal", amount: dec("15.49")),
                NewGnuCashSplit(accountName: "Liabilities:Example Card", amount: dec("-15.49")),
            ]))
        let balance = try planPayPalPayment(payment(funding: "PayPal balance"), book: book(), accounts: payPalAccounts,
                                            holdingAccount: "Expenses:Uncategorized")
        XCTAssertEqual(balance.transactions.map(\.description), ["Example Streaming"])
        assertSpendingError(.unsupportedFunding("Venmo Debit Card"),
                            try planPayPalPayment(payment(funding: "Venmo Debit Card"), book: book(), accounts: payPalAccounts,
                                                  holdingAccount: "Expenses:Uncategorized"))
    }

    func testPayPalTransactionsAlreadyInTheBookAreSkippedIndividually() throws {
        let byNum = booking("n", date(2026, 3, 30), "Example Streaming", num: "SYNTH0000TXN00042",
                            [("streaming", "15.49"), ("paypal", "-15.49")])
        let plan = try planPayPalPayment(payment(), book: book(extra: [byNum]), accounts: payPalAccounts,
                                         holdingAccount: "Expenses:Uncategorized")
        XCTAssertEqual(plan.transactions.map(\.description), ["PayPal - Collection"])
        XCTAssertEqual(plan.notes, ["Already booked: Example Streaming $15.49 on 3/30/2026"])

        let collected = booking("c", date(2026, 3, 14), "PayPal - Collection", [("paypal", "15.49"), ("bank", "-15.49")])
        let both = try planPayPalPayment(payment(), book: book(extra: [byNum, collected]), accounts: payPalAccounts,
                                         holdingAccount: "Expenses:Uncategorized")
        XCTAssertEqual(both.transactions, [])
        XCTAssertEqual(both.notes.count, 2)
    }

    func testMisconfiguredAccountsAreReported() {
        let purchase = AmexPurchase(merchant: "EXAMPLE PROPANE CO", amount: dec("42.17"), date: date(2026, 3, 12), accountEnding: nil)
        XCTAssertThrowsError(try planAmexPurchase(purchase, book: book(), amexAccount: "Liabilities:Missing Card",
                                                  holdingAccount: "Expenses:Uncategorized")) { error in
            XCTAssertEqual(error as? GnuCashError, .unknownAccount("Liabilities:Missing Card"))
        }
    }
}

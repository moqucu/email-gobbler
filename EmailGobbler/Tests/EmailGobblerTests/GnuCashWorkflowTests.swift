import Foundation
import XCTest
import EmailGobblerCore
@testable import GnuCashBook

final class GnuCashWorkflowTests: XCTestCase {
    private static let bookURL = URL(fileURLWithPath: "/tmp/Household.gnucash")
    private static let lunch = NewGnuCashTransaction(date: try! CalendarDate(year: 2026, month: 10, day: 5),
                                                     description: "Corner Café", num: "A1", splits: [
        NewGnuCashSplit(accountName: "Expenses:Dining", amount: Decimal(string: "12.5")!),
        NewGnuCashSplit(accountName: "Liabilities:Card", amount: Decimal(string: "-12.5")!),
    ])

    private struct FakeBookUseCase: GnuCashUseCase {
        var transactions = [GnuCashWorkflowTests.lunch]
        var bookURL: URL? = GnuCashWorkflowTests.bookURL
        let mailQuery = MailQuery(subjectContains: "Synthetic", senderContains: nil)
        let targets: [SheetTarget] = []
        func summarize(html: String) throws -> [String] { ["summary of \(html)"] }
        func plan(html: String, sheets: [SheetTarget: SheetSnapshot]) throws -> UseCasePlan { UseCasePlan(targets: [], notes: []) }
        func planBook(html: String, book: GnuCashBook) throws -> GnuCashPlan {
            GnuCashPlan(transactions: transactions, notes: ["book has \(book.accounts.count) accounts"])
        }
    }

    private struct AppendFailure: Error {}
    private var events: [String] = []
    private let book = GnuCashBook(bookGUID: "b", accounts: [], transactions: [])

    private func actions(read: Bool = true, append: Bool = true, consume: Bool = true, failAppend: Bool = false) -> BookActions {
        BookActions(
            readBook: read ? { [book] url in self.events.append("read \(url.lastPathComponent)"); return book } : nil,
            append: append ? { url, transactions in
                self.events.append("append \(transactions.count) to \(url.lastPathComponent)")
                if failAppend { throw AppendFailure() }
            } : nil,
            consume: consume ? { self.events.append("consume") } : nil)
    }

    func testDescribeShowsDateNumDescriptionAndSplits() {
        XCTAssertEqual(describe(Self.lunch), "10/5/2026 #A1 Corner Café: Expenses:Dining 12.5 | Liabilities:Card -12.5")
    }

    func testSummaryOnlyWithoutABookOrReader() throws {
        var noBook = FakeBookUseCase()
        noBook.bookURL = nil
        XCTAssertEqual(try processBookMessage(html: "<html>", useCase: noBook, actions: actions()),
                       MessageReport(summary: ["summary of <html>"], notes: [], targets: [], consumed: false))
        XCTAssertEqual(try processBookMessage(html: "<html>", useCase: FakeBookUseCase(),
                                              actions: actions(read: false, append: false, consume: false)).summary,
                       ["summary of <html>"])
        XCTAssertEqual(events, [])
    }

    func testPreviewReadsTheBookAndNeverWrites() throws {
        let report = try processBookMessage(html: "<html>", useCase: FakeBookUseCase(), actions: actions(append: false, consume: false))
        XCTAssertEqual(events, ["read Household.gnucash"])
        XCTAssertEqual(report, MessageReport(summary: ["summary of <html>"], notes: ["book has 0 accounts"], targets: [],
                                             consumed: false, ledgerEntries: 0, ledgerPreview: [describe(Self.lunch)]))
    }

    func testTransactionsAreAppendedBeforeTheEmailIsConsumed() throws {
        let report = try processBookMessage(html: "<html>", useCase: FakeBookUseCase(), actions: actions())
        XCTAssertEqual(events, ["read Household.gnucash", "append 1 to Household.gnucash", "consume"])
        XCTAssertEqual(report.ledgerEntries, 1)
        XCTAssertTrue(report.consumed)
    }

    func testNothingToBookStillConsumes() throws {
        var booked = FakeBookUseCase()
        booked.transactions = []
        let report = try processBookMessage(html: "<html>", useCase: booked, actions: actions())
        XCTAssertEqual(events, ["read Household.gnucash", "consume"])
        XCTAssertEqual(report.ledgerEntries, 0)
    }

    func testFailedAppendNeverConsumes() {
        XCTAssertThrowsError(try processBookMessage(html: "<html>", useCase: FakeBookUseCase(), actions: actions(failAppend: true)))
        XCTAssertEqual(events, ["read Household.gnucash", "append 1 to Household.gnucash"])
    }

    func testConsumeWithoutAppendOrAppendWithoutReadIsRejected() {
        XCTAssertThrowsError(try processBookMessage(html: "<html>", useCase: FakeBookUseCase(), actions: actions(append: false))) {
            XCTAssertEqual($0 as? WorkflowError, .invalidActions)
        }
        XCTAssertThrowsError(try processBookMessage(html: "<html>", useCase: FakeBookUseCase(), actions: actions(read: false))) {
            XCTAssertEqual($0 as? WorkflowError, .invalidActions)
        }
        XCTAssertEqual(events, [])
    }
}

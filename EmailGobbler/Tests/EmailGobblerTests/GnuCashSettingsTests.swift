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
}

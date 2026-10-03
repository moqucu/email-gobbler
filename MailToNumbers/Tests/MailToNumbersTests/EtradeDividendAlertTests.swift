import Foundation
import XCTest
import MailNumbersCore
@testable import EtradeDividends

// The fixture is anonymized from one real alert. Other inputs are constructed
// variants of its markup, not observed E*TRADE formats.
final class EtradeDividendAlertTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> CalendarDate { try! CalendarDate(year: y, month: m, day: d) }
    private func dec(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    private func fixtureHTML() throws -> String {
        guard let url = Bundle.module.url(forResource: "etrade-dividend.synthetic", withExtension: "eml", subdirectory: "Fixtures") else {
            throw XCTSkip("Missing fixture")
        }
        return try MailDecoder.html(from: Data(contentsOf: url))
    }

    private static let pair = "<strong>Security: </strong>EXAMPLE FUNDAMENTAL INDEX FUND   (EXFI)\n\t<br>\n<strong>Amount Credited: </strong>\n\t\t\t\t$12.34"

    private func alertHTML(account: String? = "XXXXX-0042",
                           sentence: String? = "You received the following dividend or interest payment(s) on 2026-03-16.",
                           payments: String = pair,
                           preview: String = "Account: XXXXX-0042 Amount Credited: $12.34") -> String {
        let accountHTML = account.map { "<p>\n<strong>Account: </strong>\($0)</p>\n" } ?? ""
        let sentenceHTML = sentence.map { "<p>\($0)</p>\n" } ?? ""
        return """
        <html><body><div class="smart-alert">
        <div class="previewHeader" style="display:none">\(preview)</div>
        <table><tr><td width="20px">&nbsp;</td><td valign="top" align="left" width="600" class="body-content">
        \(accountHTML)\(sentenceHTML)<p>
        \(payments)</p>
        <p>If you're enrolled in dividend reinvestment, your dividend will be automatically reinvested.</p>
        </td></tr></table></div></body></html>
        """
    }

    private func assertAlertError(_ expected: DividendAlertError, _ html: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try parseEtradeDividendAlert(html: html), file: file, line: line) { error in
            XCTAssertEqual(error as? DividendAlertError, expected, file: file, line: line)
        }
    }

    func testFixtureAlertIsExtracted() throws {
        let alert = try parseEtradeDividendAlert(html: try fixtureHTML())
        XCTAssertEqual(alert, DividendAlert(
            accountMask: "XXXXX-0042",
            paymentDate: date(2026, 3, 16),
            payments: [DividendPayment(security: "EXAMPLE FUNDAMENTAL INDEX FUND (EXFI)", amount: dec("12.34"))]
        ))
    }

    func testHiddenPreviewTextIsIgnored() throws {
        let alert = try parseEtradeDividendAlert(html: alertHTML(preview: "Account: XXXXX-9999 Security: OTHER (OTHR) Amount Credited: $99.99"))
        XCTAssertEqual(alert.accountMask, "XXXXX-0042")
        XCTAssertEqual(alert.payments, [DividendPayment(security: "EXAMPLE FUNDAMENTAL INDEX FUND (EXFI)", amount: dec("12.34"))])
    }

    func testSeveralPaymentsKeepDocumentOrder() throws {
        let payments = """
        <strong>Security: </strong>FIRST FUND (FRST)<br>
        <strong>Amount Credited: </strong>$1.05<br>
        <strong>Security: </strong>SECOND &amp; THIRD FUND (SCND)<br>
        <strong>Amount Credited: </strong>$1,234.56
        """
        let alert = try parseEtradeDividendAlert(html: alertHTML(payments: payments))
        XCTAssertEqual(alert.payments, [
            DividendPayment(security: "FIRST FUND (FRST)", amount: dec("1.05")),
            DividendPayment(security: "SECOND & THIRD FUND (SCND)", amount: dec("1234.56")),
        ])
    }

    func testUnsupportedOrIncompleteAlertsAreRejected() {
        assertAlertError(.unsupportedStructure, "<html><body><p>Account: XXXXX-0042</p></body></html>")
        assertAlertError(.missingAccount, alertHTML(account: nil))
        assertAlertError(.missingPaymentDate, alertHTML(sentence: nil))
        assertAlertError(.missingPaymentDate, alertHTML(sentence: "You received a payment."))
        assertAlertError(.invalidPaymentDate(text: "2026-02-30"),
                         alertHTML(sentence: "You received the following dividend or interest payment(s) on 2026-02-30."))
        assertAlertError(.missingPayments, alertHTML(payments: ""))
        assertAlertError(.unpairedPayment, alertHTML(payments: "<strong>Security: </strong>FIRST FUND (FRST)"))
        assertAlertError(.unpairedPayment, alertHTML(payments: "<strong>Amount Credited: </strong>$1.05"))
    }

    func testMalformedAmountsAreRejected() {
        for bad in ["$abc", "1.05", "$1.0.5", "-$1.05", "$"] {
            let payments = "<strong>Security: </strong>FIRST FUND (FRST)<br><strong>Amount Credited: </strong>\(bad)"
            assertAlertError(.malformedAmount(text: bad), alertHTML(payments: payments))
        }
    }
}

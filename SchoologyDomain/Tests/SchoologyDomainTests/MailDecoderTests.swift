import Foundation
import XCTest
@testable import SchoologyMailPreview

final class MailDecoderTests: XCTestCase {
    func testNestedMultipartDecodesQuotedPrintableHTML() throws {
        let message = """
        MIME-Version: 1.0\r
        Content-Type: multipart/mixed; boundary="outer"\r
        \r
        --outer\r
        Content-Type: multipart/alternative; boundary="inner"\r
        \r
        --inner\r
        Content-Type: text/plain; charset=utf-8\r
        \r
        Plain summary\r
        --inner\r
        Content-Type: text/html; charset="utf-8"\r
        Content-Transfer-Encoding: quoted-printable\r
        \r
        <p>Schoology=20summary=20=C3=A9</p>\r
        --inner--\r
        --outer--\r
        """
        XCTAssertEqual(try MailDecoder.html(from: Data(message.utf8)), "<p>Schoology summary é</p>")
    }

    func testBoundaryTextInsideHTMLIsNotARealPartDelimiter() throws {
        let message = """
        MIME-Version: 1.0\r
        Content-Type: multipart/alternative; boundary="divider"\r
        \r
        --divider\r
        Content-Type: text/html; charset=utf-8\r
        \r
        <p>Example --divider marker inside content</p>\r
        --divider--\r
        """
        XCTAssertEqual(try MailDecoder.html(from: Data(message.utf8)),
                       "<p>Example --divider marker inside content</p>")
    }

    func testBase64HTMLDecodes() throws {
        let html = "<p>Weekly summary</p>"
        let message = "Content-Type: text/html; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"
            + Data(html.utf8).base64EncodedString()
        XCTAssertEqual(try MailDecoder.html(from: Data(message.utf8)), html)
    }
}

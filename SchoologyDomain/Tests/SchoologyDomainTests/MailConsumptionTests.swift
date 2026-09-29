import Foundation
import XCTest
@testable import SchoologyMailPreview

final class MailConsumptionTests: XCTestCase {
    private enum FakeWriteError: Error { case failed }

    func testMailIsConsumedOnlyAfterVerifiedWrite() throws {
        var events: [String] = []
        try writeThenConsume(
            write: { events.append("saved and verified") },
            consume: { events.append("archived") }
        )
        XCTAssertEqual(events, ["saved and verified", "archived"])
    }

    func testFailedWriteLeavesMailUntouched() {
        var consumed = false
        XCTAssertThrowsError(try writeThenConsume(
            write: { throw FakeWriteError.failed },
            consume: { consumed = true }
        ))
        XCTAssertFalse(consumed)
    }
}

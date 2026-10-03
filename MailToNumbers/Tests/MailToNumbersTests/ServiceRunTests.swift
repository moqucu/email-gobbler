import Foundation
import XCTest
import EtradeDividends
import MailNumbersCore
@testable import MailToNumbersService

final class ServiceRunTests: XCTestCase {
    private static let ledgerTarget = SheetTarget(workbook: URL(fileURLWithPath: "/tmp/Ledger.numbers"), sheetName: "Sheet 1")

    /// Records calls and applies written plans to its in-memory sheet.
    private final class FakeClient: AutomationClient {
        var messages: [MailMessageRef] = []
        var sources: [Int32: Data] = [:]
        var sheet: SheetSnapshot
        var failListing = false
        var failFetchOf: Int32?
        var calls: [String] = []
        var backups: [URL] = []

        init(sheet: SheetSnapshot) { self.sheet = sheet }

        func listMessages(_ query: MailQuery) throws -> [MailMessageRef] {
            calls.append("list")
            struct ListFailure: Error, CustomStringConvertible { var description: String { "Mail is not running" } }
            if failListing { throw ListFailure() }
            return messages
        }

        func fetchMessage(_ ref: MailMessageRef) throws -> FetchedMailMessage {
            calls.append("fetch \(ref.id)")
            struct FetchFailure: Error, CustomStringConvertible { var description: String { "Message moved" } }
            if ref.id == failFetchOf { throw FetchFailure() }
            return FetchedMailMessage(source: sources[ref.id]!, id: ref.id, accountID: ref.accountID, rfcMessageID: ref.rfcMessageID)
        }

        func readSheet(_ target: SheetTarget) throws -> SheetSnapshot {
            calls.append("read")
            return sheet
        }

        func writeSheet(_ plan: TargetPlan, plannedFrom: SheetSnapshot, backup: URL) throws {
            calls.append("write")
            try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: backup)
            backups.append(backup)
            // Like Numbers, written rows keep the anchor row's formats.
            var rows = try plan.update.applied(to: plannedFrom).rows
            let anchor = plannedFrom.rows[plan.update.placement.anchorRow - 1]
            for target in plan.update.targetRows {
                rows[target - 1] = zip(rows[target - 1], anchor).map { written, template in
                    SheetCell(value: written.value, formatted: template.formatted, format: template.format)
                }
            }
            sheet = SheetSnapshot(rows: rows)
        }

        func consume(_ message: FetchedMailMessage) throws {
            calls.append("consume \(message.id)")
        }
    }

    private var base: URL!
    private var tick = 0

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("run-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func alertSource() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "etrade-dividend.synthetic", withExtension: "eml", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func ledger() throws -> SheetSnapshot {
        let names = DividendLedger.headers
        let header = names.map { SheetCell(value: .text($0), formatted: $0, format: .automatic) }
        let date = try CalendarDate(year: 2026, month: 3, day: 2)
        let row = [SheetCell(value: .text("E*Trade Financial"), formatted: "E*Trade Financial", format: .text),
                   SheetCell(value: .text("XXXX-0042"), formatted: "XXXX-0042", format: .text),
                   SheetCell(value: .text("Dividend or Interest Paid"), formatted: "Dividend or Interest Paid", format: .text),
                   SheetCell(value: .date(date), formatted: "3/2/2026", format: .dateAndTime),
                   SheetCell(value: .text("OLDER FUND (OLDR)"), formatted: "OLDER FUND (OLDR)", format: .text),
                   SheetCell(value: .number(1), formatted: "$1.00", format: .currency)]
        return SheetSnapshot(rows: [header, row])
    }

    private func dividends() -> ConfiguredUseCase {
        ConfiguredUseCase(id: .etradeDividends, useCase: EtradeDividendsUseCase(target: Self.ledgerTarget))
    }

    private func ref(_ id: Int32, age: Int) -> MailMessageRef {
        MailMessageRef(id: id, accountID: "ICLOUD", rfcMessageID: "<\(id)@example.invalid>", ageOffset: age)
    }

    private func environment(_ client: FakeClient, retention: Int = 30, log: @escaping (RunLogEvent) -> Void = { _ in }) -> RunEnvironment {
        RunEnvironment(client: client, backupBase: base, retention: retention, now: {
            self.tick += 1
            return Date(timeIntervalSince1970: 1_790_000_000 + Double(self.tick))
        }, log: log)
    }

    // MARK: - Runner

    func testBacklogIsProcessedInOrderAndRepeatedAlertsAreArchivedWithoutDuplicates() throws {
        let client = FakeClient(sheet: try ledger())
        client.messages = [ref(7, age: -7200), ref(8, age: -60)]
        client.sources = [7: try alertSource(), 8: try alertSource()]
        let result = runUseCase(dividends(), environment: environment(client))
        XCTAssertEqual(result, UseCaseRunResult(id: .etradeDividends, messagesFound: 2, messagesProcessed: 2, rowsWritten: 1, error: nil))
        XCTAssertEqual(client.calls, ["list", "fetch 7", "read", "write", "consume 7", "fetch 8", "read", "consume 8"])
        XCTAssertEqual(client.sheet.rowCount, 3)
        XCTAssertEqual(client.backups.map { $0.deletingLastPathComponent().path },
                       [base.appendingPathComponent("Backups/etrade-dividends").path])
    }

    func testFailureStopsTheBacklogAndLeavesLaterMessages() throws {
        let client = FakeClient(sheet: try ledger())
        client.messages = [ref(7, age: -7200), ref(8, age: -3600), ref(9, age: -60)]
        client.sources = [7: try alertSource(), 8: try alertSource(), 9: try alertSource()]
        client.failFetchOf = 8
        let result = runUseCase(dividends(), environment: environment(client))
        XCTAssertEqual(result, UseCaseRunResult(id: .etradeDividends, messagesFound: 3, messagesProcessed: 1, rowsWritten: 1,
                                                error: "Message moved"))
        XCTAssertEqual(client.calls, ["list", "fetch 7", "read", "write", "consume 7", "fetch 8"])
    }

    func testBackupsArePrunedAfterEachWrite() throws {
        let client = FakeClient(sheet: try ledger())
        let other = ["EXAMPLE FUNDAMENTAL INDEX FUND   (EXFI)": "SECOND FUND (SCND)", "$12.34": "$5.00"]
        var second = String(decoding: try alertSource(), as: UTF8.self)
        for (old, new) in other { second = second.replacingOccurrences(of: old, with: new) }
        client.messages = [ref(7, age: -7200), ref(8, age: -60)]
        client.sources = [7: try alertSource(), 8: Data(second.utf8)]
        let result = runUseCase(dividends(), environment: environment(client, retention: 1))
        XCTAssertEqual(result.rowsWritten, 2, "\(result)")
        let directory = base.appendingPathComponent("Backups/etrade-dividends")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path),
                       [client.backups.last!.lastPathComponent])
    }

    func testOneUseCaseFailingDoesNotStopTheOthers() throws {
        let failing = FakeClient(sheet: try ledger())
        failing.failListing = true
        let summary = runAll([dividends()], environment: environment(failing))
        XCTAssertEqual(summary.results, [UseCaseRunResult(id: .etradeDividends, messagesFound: 0, messagesProcessed: 0,
                                                          rowsWritten: 0, error: "Mail is not running")])
        XCTAssertFalse(summary.succeeded)

        let client = FakeClient(sheet: try ledger())
        client.messages = [ref(7, age: -60)]
        client.sources = [7: try alertSource()]
        let both = runAll([dividends(), dividends()], environment: environment(client))
        XCTAssertEqual(both.results.map(\.messagesProcessed), [1, 1])
        XCTAssertTrue(both.succeeded)
        XCTAssertLessThan(both.startedAt, both.finishedAt)
    }

    func testLogEventsCarryNoEmailContent() throws {
        let client = FakeClient(sheet: try ledger())
        client.messages = [ref(7, age: -60)]
        client.sources = [7: try alertSource()]
        var events: [RunLogEvent] = []
        _ = runUseCase(dividends(), environment: environment(client) { events.append($0) })
        XCTAssertEqual(events.map(\.stage), ["list", "process", "consume"])
        XCTAssertEqual(events.map(\.messageID), [nil, "<7@example.invalid>", "<7@example.invalid>"])
        let text = events.map { "\($0.stage) \($0.outcome)" }.joined(separator: " ")
        for secret in ["12.34", "EXFI", "EXAMPLE", "0042", "Ledger"] {
            XCTAssertFalse(text.contains(secret), "log mentions \(secret): \(text)")
        }
    }

    // MARK: - Coordinator

    private actor Gate {
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private(set) var entered = 0

        func enter() async {
            entered += 1
            await withCheckedContinuation { waiting.append($0) }
        }

        func release() {
            guard !waiting.isEmpty else { return }
            waiting.removeFirst().resume()
        }
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async {
        for _ in 0..<1_000 where !(await condition()) {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func summary() -> RunSummary {
        RunSummary(startedAt: Date(timeIntervalSince1970: 0), finishedAt: Date(timeIntervalSince1970: 1), results: [])
    }

    func testTriggersDuringARunCollapseIntoOneFollowUp() async {
        let gate = Gate()
        let coordinator = RunCoordinator { await gate.enter(); return Self.summary() }
        let first = Task { await coordinator.trigger(.launch) }
        await waitUntil { await gate.entered == 1 }
        let state = await coordinator.state
        XCTAssertEqual(state, .running)
        await coordinator.trigger(.interval)
        await coordinator.trigger(.wake)
        await coordinator.trigger(.manual)
        await gate.release()
        await waitUntil { await gate.entered == 2 }
        await gate.release()
        await first.value
        let runs = await coordinator.runCount
        let finalState = await coordinator.state
        let last = await coordinator.lastSummary
        XCTAssertEqual(runs, 2)
        XCTAssertEqual(finalState, .idle)
        XCTAssertEqual(last, Self.summary())
    }

    func testPauseBlocksAutomaticTriggersButNotRunNow() async {
        let coordinator = RunCoordinator { Self.summary() }
        await coordinator.pause()
        await coordinator.trigger(.interval)
        await coordinator.trigger(.wake)
        var runs = await coordinator.runCount
        XCTAssertEqual(runs, 0)
        let paused = await coordinator.state
        XCTAssertEqual(paused, .paused)
        await coordinator.trigger(.manual)
        runs = await coordinator.runCount
        XCTAssertEqual(runs, 1)
        let stillPaused = await coordinator.state
        XCTAssertEqual(stillPaused, .paused)
        await coordinator.resume()
        await coordinator.trigger(.interval)
        runs = await coordinator.runCount
        XCTAssertEqual(runs, 2)
        let resumed = await coordinator.state
        XCTAssertEqual(resumed, .idle)
    }

    func testStatusUpdatesArePublished() async {
        let coordinator = RunCoordinator { Self.summary() }
        let collector = Task {
            var received: [CoordinatorStatus] = []
            for await status in coordinator.updates {
                received.append(status)
                if received.count == 2 { break }
            }
            return received
        }
        await coordinator.trigger(.manual)
        let timeout = Task { try await Task.sleep(for: .seconds(2)); collector.cancel() }
        let received = await collector.value
        timeout.cancel()
        XCTAssertEqual(received, [CoordinatorStatus(state: .running, lastSummary: nil),
                                  CoordinatorStatus(state: .idle, lastSummary: Self.summary())])
    }

    // MARK: - Schedule

    private actor Recorder {
        private(set) var reasons: [TriggerReason] = []
        private(set) var sleeps: [Duration] = []
        func record(_ reason: TriggerReason) { reasons.append(reason) }
        func slept(_ duration: Duration) -> Int { sleeps.append(duration); return sleeps.count }
    }

    func testScheduleTriggersAtLaunchEveryIntervalAndOnWake() async {
        let recorder = Recorder()
        let (wakes, wakeSource) = AsyncStream.makeStream(of: Void.self)
        wakeSource.yield()
        wakeSource.yield()
        wakeSource.finish()
        await runSchedule(interval: .seconds(1800), wakes: wakes, sleep: { duration in
            if await recorder.slept(duration) > 3 { throw CancellationError() }
        }, trigger: { await recorder.record($0) })
        let reasons = await recorder.reasons
        let sleeps = await recorder.sleeps
        XCTAssertEqual(reasons.first, .launch)
        XCTAssertEqual(reasons.filter { $0 == .interval }.count, 3)
        XCTAssertEqual(reasons.filter { $0 == .wake }.count, 2)
        XCTAssertEqual(sleeps, Array(repeating: .seconds(1800), count: 4))
    }
}

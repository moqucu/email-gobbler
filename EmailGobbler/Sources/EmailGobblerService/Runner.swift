import Foundation
import EmailGobblerCore
import GnuCashBook

/// Mail and Numbers access, swappable for tests. Calls block until done.
public protocol AutomationClient {
    func listMessages(_ query: MailQuery) throws -> [MailMessageRef]
    func fetchMessage(_ ref: MailMessageRef) throws -> FetchedMailMessage
    func readSheet(_ target: SheetTarget) throws -> SheetSnapshot
    func writeSheet(_ plan: TargetPlan, plannedFrom: SheetSnapshot, backup: URL) throws
    func consume(_ message: FetchedMailMessage) throws
    func loadBook(_ url: URL) throws -> GnuCashBook
    /// Backs the book up to `backup`, then appends and verifies the transactions.
    func appendToBook(_ url: URL, _ transactions: [NewGnuCashTransaction], backup: URL) throws
}

public struct UseCaseRunResult: Equatable, Sendable {
    public let id: UseCaseID
    public let messagesFound: Int
    public let messagesProcessed: Int
    public let rowsWritten: Int
    /// Present when the use case stopped; later messages stay in the Inbox.
    public let error: String?
    /// When the last email of this run was processed and archived.
    public let lastProcessedAt: Date?

    public init(id: UseCaseID, messagesFound: Int, messagesProcessed: Int, rowsWritten: Int, error: String?,
                lastProcessedAt: Date? = nil) {
        self.id = id
        self.messagesFound = messagesFound
        self.messagesProcessed = messagesProcessed
        self.rowsWritten = rowsWritten
        self.error = error
        self.lastProcessedAt = lastProcessedAt
    }
}

public struct RunSummary: Equatable, Sendable {
    public let startedAt: Date
    public let finishedAt: Date
    public let results: [UseCaseRunResult]

    public init(startedAt: Date, finishedAt: Date, results: [UseCaseRunResult]) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.results = results
    }

    public var succeeded: Bool { results.allSatisfy { $0.error == nil } }
}

/// A log record without email content, grades, amounts, or securities.
public struct RunLogEvent: Equatable, Sendable {
    public let useCase: UseCaseID
    public let messageID: String?
    public let stage: String
    public let outcome: String

    public init(useCase: UseCaseID, messageID: String?, stage: String, outcome: String) {
        self.useCase = useCase
        self.messageID = messageID
        self.stage = stage
        self.outcome = outcome
    }
}

public struct RunEnvironment {
    public var client: any AutomationClient
    public var backupBase: URL
    public var retention: Int
    public var now: () -> Date
    public var log: (RunLogEvent) -> Void

    public init(client: any AutomationClient, backupBase: URL, retention: Int,
                now: @escaping () -> Date = Date.init, log: @escaping (RunLogEvent) -> Void = { _ in }) {
        self.client = client
        self.backupBase = backupBase
        self.retention = retention
        self.now = now
        self.log = log
    }
}

/// Processes one use case's matching Inbox messages oldest first. Each written
/// sheet is backed up first and old backups are pruned after the write; the
/// first failure stops this use case and leaves later messages in the Inbox.
public func runUseCase(_ configured: ConfiguredUseCase, environment: RunEnvironment) -> UseCaseRunResult {
    let id = configured.id
    let client = environment.client
    func log(_ messageID: String?, _ stage: String, _ outcome: String) {
        environment.log(RunLogEvent(useCase: id, messageID: messageID, stage: stage, outcome: outcome))
    }
    func failure(_ error: Error) -> String { "failed (\(type(of: error)))" }

    let messages: [MailMessageRef]
    do {
        messages = try client.listMessages(configured.useCase.mailQuery)
        log(nil, "list", "\(messages.count) found")
    } catch {
        log(nil, "list", failure(error))
        return UseCaseRunResult(id: id, messagesFound: 0, messagesProcessed: 0, rowsWritten: 0, error: "\(error)")
    }

    let directory = backupDirectory(base: environment.backupBase, useCase: id)
    var processed = 0
    var rowsWritten = 0
    var sequence = 0
    var lastProcessedAt: Date?
    for ref in messages {
        do {
            let fetched = try client.fetchMessage(ref)
            let html = try MailDecoder.html(from: fetched.source)
            if let bookUseCase = configured.useCase as? any GnuCashUseCase {
                let actions = BookActions(
                    readBook: { try client.loadBook($0) },
                    append: { url, transactions in
                        sequence += 1
                        let backup = backupURL(directory: directory, workbook: url, timestamp: environment.now(), sequence: sequence)
                        try client.appendToBook(url, transactions, backup: backup)
                        try pruneBackups(directory: directory, workbook: url, keep: environment.retention)
                    },
                    consume: { try client.consume(fetched) }
                )
                let report: MessageReport
                do {
                    report = try processBookMessage(html: html, useCase: bookUseCase, actions: actions)
                } catch let error as any EmailApplicability where error.leavesEmailInInbox {
                    log(ref.rfcMessageID, "process", "left in Inbox")
                    continue
                }
                rowsWritten += report.ledgerEntries
                log(ref.rfcMessageID, "process", "\(report.ledgerEntries) transactions added")
                log(ref.rfcMessageID, "consume", "archived")
                processed += 1
                lastProcessedAt = environment.now()
                continue
            }
            let actions = MessageActions(
                readSheet: { try client.readSheet($0) },
                write: { plan, sheet in
                    sequence += 1
                    let backup = backupURL(directory: directory, workbook: plan.target.workbook,
                                           timestamp: environment.now(), sequence: sequence)
                    try client.writeSheet(plan, plannedFrom: sheet, backup: backup)
                    try pruneBackups(directory: directory, workbook: plan.target.workbook, keep: environment.retention)
                },
                consume: { try client.consume(fetched) }
            )
            let report = try processMessage(html: html, useCase: configured.useCase, actions: actions)
            let written = report.targets.filter { $0.status == .written }
            rowsWritten += written.map(\.plannedRows).reduce(0, +)
            log(ref.rfcMessageID, "process", "\(written.count) of \(report.targets.count) sheets written")
            log(ref.rfcMessageID, "consume", "archived")
            processed += 1
            lastProcessedAt = environment.now()
        } catch {
            log(ref.rfcMessageID, "process", failure(error))
            return UseCaseRunResult(id: id, messagesFound: messages.count, messagesProcessed: processed,
                                    rowsWritten: rowsWritten, error: "\(error)", lastProcessedAt: lastProcessedAt)
        }
    }
    return UseCaseRunResult(id: id, messagesFound: messages.count, messagesProcessed: processed,
                            rowsWritten: rowsWritten, error: nil, lastProcessedAt: lastProcessedAt)
}

/// Runs every use case; one failing does not stop the others.
public func runAll(_ useCases: [ConfiguredUseCase], environment: RunEnvironment) -> RunSummary {
    let startedAt = environment.now()
    let results = useCases.map { runUseCase($0, environment: environment) }
    return RunSummary(startedAt: startedAt, finishedAt: environment.now(), results: results)
}

/// Mail and Numbers through AppleScript.
public struct LiveAutomationClient: AutomationClient {
    public init() {}

    public func listMessages(_ query: MailQuery) throws -> [MailMessageRef] { try listInboxMessages(query) }
    public func fetchMessage(_ ref: MailMessageRef) throws -> FetchedMailMessage { try fetchMailMessage(ref) }
    public func readSheet(_ target: SheetTarget) throws -> SheetSnapshot {
        try readSheetSnapshot(workbook: target.workbook, sheetName: target.sheetName)
    }
    public func writeSheet(_ plan: TargetPlan, plannedFrom: SheetSnapshot, backup: URL) throws {
        try writeSheetUpdate(workbook: plan.target.workbook, sheetName: plan.target.sheetName,
                             plan: plan.update, plannedFrom: plannedFrom, backup: backup)
    }
    public func consume(_ message: FetchedMailMessage) throws { try consumeMailMessage(message) }
    public func loadBook(_ url: URL) throws -> GnuCashBook { try GnuCashBookStore(url: url).load() }
    public func appendToBook(_ url: URL, _ transactions: [NewGnuCashTransaction], backup: URL) throws {
        try GnuCashBookStore(url: url).append(transactions, backupDirectory: backup.deletingLastPathComponent())
    }
}

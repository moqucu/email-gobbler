import Foundation
import MailNumbersCore

/// Mail and Numbers access, swappable for tests. Calls block until done.
public protocol AutomationClient {
    func listMessages(_ query: MailQuery) throws -> [MailMessageRef]
    func fetchMessage(_ ref: MailMessageRef) throws -> FetchedMailMessage
    func readSheet(_ target: SheetTarget) throws -> SheetSnapshot
    func writeSheet(_ plan: TargetPlan, plannedFrom: SheetSnapshot, backup: URL) throws
    func consume(_ message: FetchedMailMessage) throws
}

public struct UseCaseRunResult: Equatable, Sendable {
    public let id: UseCaseID
    public let messagesFound: Int
    public let messagesProcessed: Int
    public let rowsWritten: Int
    /// Present when the use case stopped; later messages stay in the Inbox.
    public let error: String?

    public init(id: UseCaseID, messagesFound: Int, messagesProcessed: Int, rowsWritten: Int, error: String?) {
        self.id = id
        self.messagesFound = messagesFound
        self.messagesProcessed = messagesProcessed
        self.rowsWritten = rowsWritten
        self.error = error
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

public func runUseCase(_ configured: ConfiguredUseCase, environment: RunEnvironment) -> UseCaseRunResult {
    UseCaseRunResult(id: configured.id, messagesFound: 0, messagesProcessed: 0, rowsWritten: 0, error: "not implemented")
}

public func runAll(_ useCases: [ConfiguredUseCase], environment: RunEnvironment) -> RunSummary {
    RunSummary(startedAt: environment.now(), finishedAt: environment.now(), results: [])
}

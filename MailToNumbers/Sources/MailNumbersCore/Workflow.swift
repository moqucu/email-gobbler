import Foundation

public struct MailQuery: Equatable {
    public let subjectContains: String
    public let senderContains: String?

    public init(subjectContains: String, senderContains: String?) {
        self.subjectContains = subjectContains
        self.senderContains = senderContains
    }
}

public struct UseCasePlan: Equatable {
    public let update: SheetUpdatePlan
    /// Human-readable notes such as ignored courses or already recorded payments.
    public let notes: [String]

    public init(update: SheetUpdatePlan, notes: [String]) {
        self.update = update
        self.notes = notes
    }
}

/// One kind of email that updates one kind of Numbers sheet.
public protocol MailToNumbersUseCase {
    var mailQuery: MailQuery { get }
    func summarize(html: String) throws -> [String]
    func plan(html: String, sheet: SheetSnapshot) throws -> UseCasePlan
}

public struct MessageActions {
    public var readSheet: (() throws -> SheetSnapshot)?
    public var write: ((SheetUpdatePlan, SheetSnapshot) throws -> Void)?
    public var consume: (() throws -> Void)?

    public init(readSheet: (() throws -> SheetSnapshot)? = nil,
                write: ((SheetUpdatePlan, SheetSnapshot) throws -> Void)? = nil,
                consume: (() throws -> Void)? = nil) {
        self.readSheet = readSheet
        self.write = write
        self.consume = consume
    }
}

public enum MessageOutcome: Equatable {
    case summarized
    case previewed(rows: Int)
    case written(rows: Int)
    case nothingToWrite
}

public enum WorkflowError: Error, Equatable {
    case notImplemented
    case invalidActions
}

public func processMessage(html: String, useCase: some MailToNumbersUseCase, actions: MessageActions,
                           report: (String) -> Void) throws -> MessageOutcome {
    throw WorkflowError.notImplemented
}

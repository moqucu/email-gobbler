import Foundation

public struct ForegroundSnapshot: Equatable, Sendable {
    public let frontmostPID: Int32?
    public let numbersPID: Int32?
    public let numbersHidden: Bool

    public init(frontmostPID: Int32?, numbersPID: Int32?, numbersHidden: Bool) {
        self.frontmostPID = frontmostPID
        self.numbersPID = numbersPID
        self.numbersHidden = numbersHidden
    }

    public var numbersRunning: Bool { numbersPID != nil }
}

public enum ForegroundAction: Equatable, Sendable {
    case hideNumbers
    case activate(pid: Int32)
}

/// Undoes what a run did to the screen: hide Numbers if the run launched or
/// unhid it, and give focus back if Numbers took it.
public func foregroundActions(before: ForegroundSnapshot, after: ForegroundSnapshot) -> [ForegroundAction] { [] }

public struct FailureNotice: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// A notification for use cases that newly stopped; it names use cases only.
public func failureNotice(previous: RunSummary?, current: RunSummary) -> FailureNotice? { nil }

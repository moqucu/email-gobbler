import Foundation

public struct ForegroundSnapshot: Equatable, Sendable {
    public let frontmostPID: Int32?
    public let numbersPID: Int32?
    public let numbersHidden: Bool
    public let mailPID: Int32?

    public init(frontmostPID: Int32?, numbersPID: Int32?, numbersHidden: Bool, mailPID: Int32? = nil) {
        self.frontmostPID = frontmostPID
        self.numbersPID = numbersPID
        self.numbersHidden = numbersHidden
        self.mailPID = mailPID
    }

    public var numbersRunning: Bool { numbersPID != nil }
}

public enum ForegroundAction: Equatable, Sendable {
    case hideNumbers
    case hideMail
    case activate(pid: Int32)
}

/// Undoes what a run did to the screen: hide Numbers if the run launched or
/// unhid it, hide Mail only if the run launched it, and give focus back once if
/// either took it. Nothing changes while the user is working in Mail or Numbers.
public func foregroundActions(before: ForegroundSnapshot, after: ForegroundSnapshot) -> [ForegroundAction] {
    let userApp = before.frontmostPID
    let userWasInNumbers = before.numbersRunning && userApp == before.numbersPID
    let userWasInMail = before.mailPID != nil && userApp == before.mailPID
    guard !userWasInNumbers, !userWasInMail else { return [] }

    var actions: [ForegroundAction] = []
    if after.numbersRunning && !after.numbersHidden && (!before.numbersRunning || before.numbersHidden) {
        actions.append(.hideNumbers)
    }
    if before.mailPID == nil && after.mailPID != nil {
        actions.append(.hideMail)
    }
    let tookFocus = after.frontmostPID != nil
        && (after.frontmostPID == after.numbersPID || after.frontmostPID == after.mailPID)
    if tookFocus, let userApp { actions.append(.activate(pid: userApp)) }
    return actions
}

public struct FailureNotice: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// A notification for use cases that newly stopped; it names use cases only.
public func failureNotice(previous: RunSummary?, current: RunSummary) -> FailureNotice? {
    let known = Set((previous?.results ?? []).compactMap { result in result.error.map { "\(result.id.rawValue)\u{0}\($0)" } })
    let newlyStopped = current.results.filter { result in
        guard let error = result.error else { return false }
        return !known.contains("\(result.id.rawValue)\u{0}\(error)")
    }.map(\.id.displayName)
    guard let last = newlyStopped.last else { return nil }
    let names = newlyStopped.count == 1 ? last : newlyStopped.dropLast().joined(separator: ", ") + " and " + last
    return FailureNotice(title: "EmailGobbler needs attention",
                         body: "\(names) stopped. Open the EmailGobbler menu for details.")
}

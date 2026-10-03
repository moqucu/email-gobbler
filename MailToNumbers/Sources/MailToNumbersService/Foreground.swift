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
/// unhid it, and give focus back if Numbers took it.
public func foregroundActions(before: ForegroundSnapshot, after: ForegroundSnapshot) -> [ForegroundAction] {
    let userWasInNumbers = before.numbersRunning && before.frontmostPID == before.numbersPID
    guard !userWasInNumbers, after.numbersRunning else { return [] }
    var actions: [ForegroundAction] = []
    let launchedByRun = !before.numbersRunning
    let unhiddenByRun = before.numbersHidden
    if !after.numbersHidden && (launchedByRun || unhiddenByRun) { actions.append(.hideNumbers) }
    if after.frontmostPID == after.numbersPID, let previous = before.frontmostPID { actions.append(.activate(pid: previous)) }
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

import Foundation

extension UseCaseID {
    public var displayName: String {
        switch self {
        case .schoologyGrades: return "Schoology grades"
        case .etradeDividends: return "E*TRADE dividends"
        }
    }
}

/// What the menu bar shows. Built from coordinator status and settings only.
public struct MenuStatus: Equatable, Sendable {
    public enum Symbol: String, Sendable {
        case idle = "tray.and.arrow.down"
        case running = "arrow.triangle.2.circlepath"
        case paused = "pause.circle"
        case attention = "exclamationmark.triangle"
    }

    public let symbol: Symbol
    public let headline: String
    public let details: [String]
    public let pauseTitle: String

    public init(symbol: Symbol, headline: String, details: [String], pauseTitle: String) {
        self.symbol = symbol
        self.headline = headline
        self.details = details
        self.pauseTitle = pauseTitle
    }
}

private func plural(_ count: Int, _ word: String) -> String {
    "\(count) \(word)\(count == 1 ? "" : "s")"
}

private func describe(_ result: UseCaseRunResult) -> String {
    let name = result.id.displayName
    if let error = result.error {
        return "\(name): stopped after \(result.messagesProcessed) of \(result.messagesFound) emails: \(error)"
    }
    guard result.messagesFound > 0 else { return "\(name): no new email" }
    return "\(name): \(plural(result.messagesProcessed, "email")), \(plural(result.rowsWritten, "row")) written"
}

/// Settings problems come first, then a running or paused state, then the last
/// run's outcome. Details may include error text but never reach the log.
public func menuStatus(status: CoordinatorStatus, settingsIssues: [SettingsIssue], hasEnabledUseCases: Bool,
                       formatTime: (Date) -> String) -> MenuStatus {
    let pauseTitle = status.state == .paused ? "Resume" : "Pause"
    if !settingsIssues.isEmpty {
        return MenuStatus(symbol: .attention, headline: "Settings need attention",
                          details: settingsIssues.map(\.message), pauseTitle: pauseTitle)
    }
    if !hasEnabledUseCases {
        return MenuStatus(symbol: .attention, headline: "Not set up",
                          details: ["Open Settings… to choose workbooks"], pauseTitle: pauseTitle)
    }
    let details = status.lastSummary.map { summary in
        ["Last run: \(formatTime(summary.finishedAt))"] + summary.results.map(describe)
    } ?? []
    switch status.state {
    case .running:
        return MenuStatus(symbol: .running, headline: "Checking mail…", details: details, pauseTitle: pauseTitle)
    case .paused:
        return MenuStatus(symbol: .paused, headline: "Paused", details: details, pauseTitle: pauseTitle)
    case .idle:
        guard let summary = status.lastSummary else {
            return MenuStatus(symbol: .idle, headline: "Waiting for the first run", details: [], pauseTitle: pauseTitle)
        }
        return summary.succeeded
            ? MenuStatus(symbol: .idle, headline: "Up to date", details: details, pauseTitle: pauseTitle)
            : MenuStatus(symbol: .attention, headline: "Last run stopped", details: details, pauseTitle: pauseTitle)
    }
}

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

public func menuStatus(status: CoordinatorStatus, settingsIssues: [SettingsIssue], hasEnabledUseCases: Bool,
                       formatTime: (Date) -> String) -> MenuStatus {
    MenuStatus(symbol: .idle, headline: "", details: [], pauseTitle: "")
}

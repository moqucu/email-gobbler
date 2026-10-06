import Foundation

/// When each use case last processed an email, kept across runs and relaunches.
public struct ProcessingHistory: Codable, Equatable, Sendable {
    /// Keyed by `UseCaseID.rawValue`.
    public var lastProcessed: [String: Date]

    public init(lastProcessed: [String: Date] = [:]) {
        self.lastProcessed = lastProcessed
    }

    public func lastProcessed(_ id: UseCaseID) -> Date? { nil }

    public func recording(_ summary: RunSummary) -> ProcessingHistory { self }
}

public struct ProcessingHistoryStore: Sendable {
    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("history.json")
    }

    public static var standard: ProcessingHistoryStore {
        ProcessingHistoryStore(directory: SettingsStore.standard.fileURL.deletingLastPathComponent())
    }

    public func load() -> ProcessingHistory { ProcessingHistory() }
    public func save(_ history: ProcessingHistory) throws {}
}

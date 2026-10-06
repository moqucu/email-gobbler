import Foundation

/// When each use case last processed an email, kept across runs and relaunches.
public struct ProcessingHistory: Codable, Equatable, Sendable {
    /// Keyed by `UseCaseID.rawValue`.
    public var lastProcessed: [String: Date]

    public init(lastProcessed: [String: Date] = [:]) {
        self.lastProcessed = lastProcessed
    }

    public func lastProcessed(_ id: UseCaseID) -> Date? { lastProcessed[id.rawValue] }

    public func recording(_ summary: RunSummary) -> ProcessingHistory {
        var updated = self
        for result in summary.results {
            if let date = result.lastProcessedAt { updated.lastProcessed[result.id.rawValue] = date }
        }
        return updated
    }
}

public struct ProcessingHistoryStore: Sendable {
    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("history.json")
    }

    public static var standard: ProcessingHistoryStore {
        ProcessingHistoryStore(directory: SettingsStore.standard.fileURL.deletingLastPathComponent())
    }

    /// Missing or unreadable history starts empty; it only feeds the menu.
    public func load() -> ProcessingHistory {
        guard let data = try? Data(contentsOf: fileURL),
              let history = try? Self.decoder.decode(ProcessingHistory.self, from: data) else { return ProcessingHistory() }
        return history
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func save(_ history: ProcessingHistory) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(history).write(to: fileURL, options: .atomic)
    }
}

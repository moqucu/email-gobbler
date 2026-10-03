import Foundation

public enum TriggerReason: Equatable, Sendable {
    case launch
    case interval
    case wake
    case manual
}

public enum CoordinatorState: Equatable, Sendable {
    case idle
    case running
    case paused
}

public struct CoordinatorStatus: Equatable, Sendable {
    public let state: CoordinatorState
    public let lastSummary: RunSummary?

    public init(state: CoordinatorState, lastSummary: RunSummary?) {
        self.state = state
        self.lastSummary = lastSummary
    }
}

/// Runs at most one run at a time and collapses triggers that arrive during a
/// run into one follow-up run. Pausing blocks automatic triggers, not Run Now.
public actor RunCoordinator {
    public nonisolated let updates: AsyncStream<CoordinatorStatus>
    private let continuation: AsyncStream<CoordinatorStatus>.Continuation
    private let run: @Sendable () async -> RunSummary

    public private(set) var state: CoordinatorState = .idle
    public private(set) var lastSummary: RunSummary?
    public private(set) var runCount = 0

    public init(run: @escaping @Sendable () async -> RunSummary) {
        self.run = run
        (updates, continuation) = AsyncStream.makeStream(of: CoordinatorStatus.self)
    }

    public func trigger(_ reason: TriggerReason) async {}
    public func pause() {}
    public func resume() {}
}

/// Triggers a launch run, then interval runs, and a run after each wake, until
/// the interval sleep throws (for example on cancellation) and wakes finish.
public func runSchedule(interval: Duration,
                        wakes: AsyncStream<Void>,
                        sleep: @escaping @Sendable (Duration) async throws -> Void,
                        trigger: @escaping @Sendable (TriggerReason) async -> Void) async {}

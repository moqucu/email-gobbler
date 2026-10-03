import AppKit
import Foundation
import MailNumbersCore
import MailToNumbersService

/// Mail and Numbers scripting runs one script at a time, off the main thread.
private let automationQueue = DispatchQueue(label: "com.moqucu.MailToNumbers.automation", qos: .utility)

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var menu: MenuStatus
    @Published private(set) var isRunning = false

    private let store = SettingsStore.standard
    private let settings: AppSettings
    private let settingsIssues: [SettingsIssue]
    private let coordinator: RunCoordinator
    private var status = CoordinatorStatus(state: .idle, lastSummary: nil)
    private var tasks: [Task<Void, Never>] = []

    private var supportDirectory: URL { store.fileURL.deletingLastPathComponent() }
    private var canRun: Bool { settingsIssues.isEmpty && !settings.configuredUseCases().isEmpty }

    init() {
        var issues: [SettingsIssue] = []
        let loaded: AppSettings
        do {
            loaded = try store.load()
        } catch {
            loaded = .standard
            issues.append(SettingsIssue(field: "settings", message: "\(error)"))
        }
        issues += loaded.validate()
        settings = loaded
        settingsIssues = issues

        let runnable = issues.isEmpty ? loaded : nil
        let backupBase = store.fileURL.deletingLastPathComponent()
        coordinator = RunCoordinator {
            await withCheckedContinuation { continuation in
                automationQueue.async {
                    let useCases = runnable?.configuredUseCases() ?? []
                    let environment = RunEnvironment(client: LiveAutomationClient(), backupBase: backupBase,
                                                     retention: runnable?.backupRetention ?? 1, log: unifiedLog)
                    continuation.resume(returning: runAll(useCases, environment: environment))
                }
            }
        }
        menu = MenuStatus(symbol: .idle, headline: "Starting…", details: [], pauseTitle: "Pause")
        refresh()
        start()
    }

    private func start() {
        let coordinator = coordinator
        tasks.append(Task { [weak self] in
            for await status in coordinator.updates {
                self?.status = status
                self?.refresh()
            }
        })
        guard canRun else { return }
        let interval = Duration.seconds(settings.intervalMinutes * 60)
        tasks.append(Task {
            await runSchedule(interval: interval, wakes: wakeNotifications(),
                              sleep: { try await Task.sleep(for: $0) },
                              trigger: { await coordinator.trigger($0) })
        })
    }

    private func refresh() {
        isRunning = status.state == .running
        menu = menuStatus(status: status, settingsIssues: settingsIssues,
                          hasEnabledUseCases: !settings.configuredUseCases().isEmpty,
                          formatTime: { $0.formatted(date: .abbreviated, time: .shortened) })
    }

    func runNow() {
        let coordinator = coordinator
        Task { await coordinator.trigger(.manual) }
    }

    func togglePause() {
        let coordinator = coordinator
        let paused = status.state == .paused
        Task { paused ? await coordinator.resume() : await coordinator.pause() }
    }

    /// Until the settings window exists, settings are edited as JSON and apply after relaunch.
    func showSettingsFile() {
        if !FileManager.default.fileExists(atPath: store.fileURL.path) {
            try? store.save(settings)
        }
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    func showBackups() {
        let backups = supportDirectory.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        NSWorkspace.shared.open(backups)
    }
}

private final class ObserverToken: @unchecked Sendable {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
}

/// Yields after the Mac wakes from sleep.
func wakeNotifications() -> AsyncStream<Void> {
    AsyncStream { continuation in
        let center = NSWorkspace.shared.notificationCenter
        let observer = ObserverToken(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { _ in
            continuation.yield()
        })
        continuation.onTermination = { _ in
            NSWorkspace.shared.notificationCenter.removeObserver(observer.token)
        }
    }
}

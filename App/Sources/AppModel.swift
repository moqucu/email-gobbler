import AppKit
import Foundation
import EmailGobblerCore
import EmailGobblerService

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var menu = MenuStatus(symbol: .idle, headline: "Starting…", details: [], pauseTitle: "Pause")
    @Published private(set) var isRunning = false

    private let store = SettingsStore.standard
    private let settingsWindow = SettingsWindowController()
    private var settings = AppSettings.standard
    private var settingsIssues: [SettingsIssue] = []
    private var coordinator: RunCoordinator?
    private var status = CoordinatorStatus(state: .idle, lastSummary: nil)
    private var paused = false
    private var tasks: [Task<Void, Never>] = []

    private var supportDirectory: URL { store.fileURL.deletingLastPathComponent() }
    private var canRun: Bool { settingsIssues.isEmpty && !settings.configuredUseCases().isEmpty }

    init() {
        _ = try? migrateLegacyDirectory(from: SettingsStore.legacyDirectory,
                                        to: SettingsStore.standard.fileURL.deletingLastPathComponent())
        let firstLaunch = !FileManager.default.fileExists(atPath: store.fileURL.path)
        do {
            apply(try store.load())
        } catch {
            settingsIssues = [SettingsIssue(field: "settings", message: "\(error)")]
            refresh()
        }
        if firstLaunch {
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        }
    }

    /// Replaces the coordinator and schedule for new settings. Scripting stays
    /// serialized on the automation queue, so an old run cannot overlap a new one.
    private func apply(_ newSettings: AppSettings) {
        tasks.forEach { $0.cancel() }
        tasks = []
        settings = newSettings
        settingsIssues = newSettings.validate()
        status = CoordinatorStatus(state: paused ? .paused : .idle, lastSummary: status.lastSummary)

        let runnable = settingsIssues.isEmpty ? newSettings : nil
        let backupBase = supportDirectory
        let coordinator = RunCoordinator {
            let before = await ForegroundGuard.snapshot()
            let summary = await onAutomationQueue {
                let environment = RunEnvironment(client: LiveAutomationClient(), backupBase: backupBase,
                                                 retention: runnable?.backupRetention ?? 1, log: unifiedLog)
                return runAll(runnable?.configuredUseCases() ?? [], environment: environment)
            }
            await ForegroundGuard.restore(before: before)
            return summary
        }
        self.coordinator = coordinator
        refresh()

        tasks.append(Task { [weak self] in
            for await update in coordinator.updates {
                guard let self else { return }
                if update.state != .running, let finished = update.lastSummary, finished != status.lastSummary,
                   let notice = failureNotice(previous: status.lastSummary, current: finished) {
                    FailureNotifier.post(notice)
                }
                status = update
                refresh()
            }
        })
        let wasPaused = paused
        let interval = Duration.seconds(newSettings.intervalMinutes * 60)
        let scheduled = canRun
        tasks.append(Task {
            if wasPaused { await coordinator.pause() }
            guard scheduled else { return }
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
        guard let coordinator else { return }
        Task { await coordinator.trigger(.manual) }
    }

    func togglePause() {
        guard let coordinator else { return }
        paused.toggle()
        let pause = paused
        Task { pause ? await coordinator.pause() : await coordinator.resume() }
    }

    func showSettings() {
        settingsWindow.show(settings: settings, savedSettingsValid: canRun) { [weak self] saved in
            guard let self else { return }
            do {
                try store.save(saved)
                apply(saved)
            } catch {
                settingsIssues = [SettingsIssue(field: "settings", message: "Settings could not be saved: \(error)")]
                refresh()
            }
        }
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

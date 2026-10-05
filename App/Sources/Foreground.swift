import AppKit
import MailToNumbersService
@preconcurrency import UserNotifications

/// Reads and restores what is on screen around a run.
@MainActor
enum ForegroundGuard {
    private static var numbers: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Numbers").first
    }

    private static var mail: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").first
    }

    static func snapshot() -> ForegroundSnapshot {
        ForegroundSnapshot(frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                           numbersPID: numbers?.processIdentifier, numbersHidden: numbers?.isHidden ?? false,
                           mailPID: mail?.processIdentifier)
    }

    static func restore(before: ForegroundSnapshot) {
        for action in foregroundActions(before: before, after: snapshot()) {
            switch action {
            case .hideNumbers:
                numbers?.hide()
            case .hideMail:
                mail?.hide()
            case .activate(let pid):
                NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            }
        }
    }
}

/// Posts failure notices; they name use cases only, never email content.
@MainActor
enum FailureNotifier {
    static func post(_ notice: FailureNotice) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

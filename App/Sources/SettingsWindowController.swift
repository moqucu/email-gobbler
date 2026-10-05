import AppKit
import EmailGobblerService
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(settings: AppSettings, savedSettingsValid: Bool, onSave: @escaping (AppSettings) -> Void) {
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let editor = SettingsEditor(settings: settings, savedSettingsValid: savedSettingsValid, onSave: onSave)
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(editor: editor)))
        window.title = "EmailGobbler Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

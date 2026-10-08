import AppKit
import EmailGobblerService
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var editor: SettingsEditor?

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
        window.delegate = self
        window.center()
        editor.onClose = { [weak window] in window?.close() }
        self.editor = editor
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The close button acts like Cancel: unsaved changes need confirmation.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let editor, editor.hasChanges else { return true }
        editor.cancel()
        return false
    }
}

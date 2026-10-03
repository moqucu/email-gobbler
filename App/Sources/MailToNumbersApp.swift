import AppKit
import SwiftUI

@main
struct MailToNumbersApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.menu.symbol.rawValue)
                .accessibilityLabel("Mail to Numbers: \(model.menu.headline)")
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Text(model.menu.headline)
        ForEach(Array(model.menu.details.enumerated()), id: \.offset) { _, line in
            Text(line)
        }
        Divider()
        Button("Run Now") { model.runNow() }
            .keyboardShortcut("r")
            .disabled(model.isRunning)
        Button(model.menu.pauseTitle) { model.togglePause() }
        Divider()
        Button("Settings…") { model.showSettings() }
            .keyboardShortcut(",")
        Button("Show Backups") { model.showBackups() }
        Divider()
        Button("Quit Mail to Numbers") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

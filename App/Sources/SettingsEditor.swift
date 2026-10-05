import AppKit
import Foundation
import EmailGobblerCore
import EmailGobblerService
import GnuCashBook
import UniformTypeIdentifiers

@MainActor
final class SettingsEditor: ObservableObject {
    @Published var draft: AppSettings
    @Published private(set) var sheetNames: [String: [String]] = [:]
    @Published private(set) var issues: [SettingsIssue] = []
    @Published private(set) var isChecking = false
    @Published private(set) var message: String?
    @Published private(set) var loginState = LoginItem.state
    @Published private(set) var hasValidSavedSettings: Bool
    @Published private(set) var bookSummary: String?

    private let onSave: (AppSettings) -> Void

    init(settings: AppSettings, savedSettingsValid: Bool, onSave: @escaping (AppSettings) -> Void) {
        draft = settings
        hasValidSavedSettings = savedSettingsValid
        self.onSave = onSave
        for path in workbookPaths { loadSheetNames(path) }
        loadBookSummary()
    }

    func chooseGnuCashBook() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gnucash") ?? .data, .xml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Mobile Documents/com~apple~CloudDocs")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.gnuCash.bookPath = url.path
        loadBookSummary()
    }

    func removeGnuCashBook() {
        draft.gnuCash.bookPath = nil
        bookSummary = nil
    }

    /// Reads the chosen book in the background; GnuCash itself is not involved.
    private func loadBookSummary() {
        guard let path = draft.gnuCash.bookPath, !path.isEmpty else {
            bookSummary = nil
            return
        }
        bookSummary = "Reading \(URL(fileURLWithPath: path).lastPathComponent)…"
        Task {
            let summary = await Task.detached(priority: .utility) { () -> String in
                let url = URL(fileURLWithPath: path)
                do {
                    return gnuCashBookSummary(try GnuCashBookStore(url: url).load(), fileName: url.lastPathComponent)
                } catch {
                    return "\(url.lastPathComponent): \(error)"
                }
            }.value
            if draft.gnuCash.bookPath == path { bookSummary = summary }
        }
    }

    private var workbookPaths: [String] {
        (draft.grades.routes.map(\.workbookPath) + [draft.dividends.workbookPath ?? ""]).filter { !$0.isEmpty }
    }

    func issue(_ field: String) -> String? {
        let messages = issues.filter { $0.field == field }.map(\.message)
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    func chooseWorkbook(_ assign: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "numbers") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Mobile Documents/com~apple~Numbers/Documents")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        assign(url.path)
        loadSheetNames(url.path)
    }

    func loadSheetNames(_ path: String) {
        guard !path.isEmpty, sheetNames[path] == nil else { return }
        Task {
            let names = await onAutomationQueue { (try? readSheetNames(workbook: URL(fileURLWithPath: path))) ?? [] }
            sheetNames[path] = names
        }
    }

    func addStudent() {
        draft.grades.routes.append(StudentRouteSettings(studentLabel: "", workbookPath: "", sheetName: ""))
    }

    func removeStudent(at index: Int) {
        guard draft.grades.routes.indices.contains(index) else { return }
        draft.grades.routes.remove(at: index)
    }

    /// Validates, reads every enabled sheet, and saves only when nothing needs fixing.
    func save() {
        message = nil
        issues = draft.validate()
        guard issues.isEmpty else {
            message = "Fix the highlighted settings, then save again."
            return
        }
        isChecking = true
        let settings = draft
        Task {
            let found = await onAutomationQueue {
                preflightIssues(settings) { try readSheetSnapshot(workbook: $0.workbook, sheetName: $0.sheetName) }
            }
            isChecking = false
            issues = found
            guard found.isEmpty else {
                message = "Some sheets need attention in Numbers. Nothing was saved."
                return
            }
            onSave(settings)
            hasValidSavedSettings = true
            message = "Saved. The new settings are active."
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            message = "Launch at Login could not be changed: \(error.localizedDescription)"
        }
        loginState = LoginItem.state
    }

    func refreshLoginState() {
        loginState = LoginItem.state
    }
}

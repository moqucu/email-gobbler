import AppKit
import Foundation
import EmailGobblerCore
import EmailGobblerService
import GnuCashBook
import SpendingEmails
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
    /// Accounts in the chosen book that fit each role, for the pickers.
    @Published private(set) var bookAccounts: [SpendingAccountRole: [String]] = [:]
    @Published var isConfirmingDiscard = false

    /// The settings as last saved; the draft differs from them while there are unsaved changes.
    private var saved: AppSettings
    private let onSave: (AppSettings) -> Void
    /// Closes the settings window.
    var onClose: () -> Void = {}

    init(settings: AppSettings, savedSettingsValid: Bool, onSave: @escaping (AppSettings) -> Void) {
        draft = settings
        saved = settings
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
        bookAccounts = [:]
    }

    /// Reads the chosen book in the background; GnuCash itself is not involved.
    private func loadBookSummary() {
        guard let path = draft.gnuCash.bookPath, !path.isEmpty else {
            bookSummary = nil
            bookAccounts = [:]
            return
        }
        bookSummary = "Reading \(URL(fileURLWithPath: path).lastPathComponent)…"
        Task {
            let (summary, accounts) = await Task.detached(priority: .utility) { () -> (String, [SpendingAccountRole: [String]]) in
                let url = URL(fileURLWithPath: path)
                do {
                    let book = try GnuCashBookStore(url: url).load()
                    let accounts = Dictionary(uniqueKeysWithValues: SpendingAccountRole.allCases.map {
                        ($0, postableAccountNames(book, for: $0))
                    })
                    return (gnuCashBookSummary(book, fileName: url.lastPathComponent), accounts)
                } catch {
                    return ("\(url.lastPathComponent): \(error)", [:])
                }
            }.value
            guard draft.gnuCash.bookPath == path else { return }
            bookSummary = summary
            bookAccounts = accounts
        }
    }

    private var workbookPaths: [String] {
        (draft.grades.routes.map(\.workbookPath) + [draft.dividends.workbookPath ?? ""]).filter { !$0.isEmpty }
    }

    var hasChanges: Bool { draft != saved }

    /// Closes at once without changes; otherwise asks whether to discard them.
    func cancel() {
        if hasChanges {
            isConfirmingDiscard = true
        } else {
            onClose()
        }
    }

    func discardChanges() {
        draft = saved
        isConfirmingDiscard = false
        onClose()
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
                message = "Some settings need attention. Nothing was saved."
                return
            }
            onSave(settings)
            saved = settings
            hasValidSavedSettings = true
            // Edits made while the check ran stay open for another save.
            guard draft == settings else {
                message = "Saved. You changed more since; save again to keep those changes."
                return
            }
            onClose()
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

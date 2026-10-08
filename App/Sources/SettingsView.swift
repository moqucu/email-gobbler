import EmailGobblerService
import SwiftUI

struct SettingsView: View {
    @ObservedObject var editor: SettingsEditor

    var body: some View {
        VStack(spacing: 0) {
            Form {
                dividendsSection
                gradesSection
                gnuCashSection
                spendingSection
                scheduleSection
                startupSection
            }
            .formStyle(.grouped)
            footer
        }
        .frame(minWidth: 560, minHeight: 600)
        .onAppear { editor.refreshLoginState() }
    }

    private var dividendsSection: some View {
        Section("E*TRADE dividends") {
            Toggle("Record dividend and interest alerts", isOn: $editor.draft.dividends.enabled)
            if editor.draft.dividends.enabled {
                WorkbookRow(path: editor.draft.dividends.workbookPath ?? "",
                            issue: editor.issue("dividends.workbookPath")) {
                    editor.chooseWorkbook { editor.draft.dividends.workbookPath = $0 }
                }
                SheetRow(sheet: $editor.draft.dividends.sheetName,
                         names: editor.sheetNames[editor.draft.dividends.workbookPath ?? ""],
                         issue: editor.issue("dividends.sheetName"))
            }
        }
    }

    private var gradesSection: some View {
        Section {
            Toggle("Record weekly Schoology grades", isOn: $editor.draft.grades.enabled)
            if editor.draft.grades.enabled {
                ForEach(Array(editor.draft.grades.routes.indices), id: \.self) { index in
                    studentRows(index)
                }
                Button("Add Student") { editor.addStudent() }
                if let issue = editor.issue("grades.routes") { IssueText(issue) }
            }
        } header: {
            Text("Schoology grades")
        } footer: {
            Text("Students in the email without a sheet here are ignored.")
        }
    }

    @ViewBuilder
    private func studentRows(_ index: Int) -> some View {
        let route = $editor.draft.grades.routes[index]
        let prefix = "grades.routes[\(index)]"
        HStack {
            TextField("Student name as shown in the email", text: route.studentLabel)
            Button(role: .destructive) { editor.removeStudent(at: index) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove this student")
        }
        if let issue = editor.issue("\(prefix).studentLabel") { IssueText(issue) }
        WorkbookRow(path: route.wrappedValue.workbookPath, issue: editor.issue("\(prefix).workbookPath")) {
            editor.chooseWorkbook { route.wrappedValue.workbookPath = $0 }
        }
        SheetRow(sheet: route.sheetName, names: editor.sheetNames[route.wrappedValue.workbookPath],
                 issue: editor.issue("\(prefix).sheetName"))
    }

    private var gnuCashSection: some View {
        Section {
            HStack {
                Text("Book")
                Spacer()
                Text(editor.draft.gnuCash.bookPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "None")
                    .foregroundStyle(.secondary)
                    .help(editor.draft.gnuCash.bookPath ?? "")
                Button("Choose…") { editor.chooseGnuCashBook() }
                if editor.draft.gnuCash.bookPath != nil {
                    Button("Remove") { editor.removeGnuCashBook() }
                }
            }
            if let summary = editor.bookSummary {
                Text(summary).foregroundStyle(.secondary)
            }
            if let issue = editor.issue("gnuCash.bookPath") { IssueText(issue) }
        } header: {
            Text("GnuCash")
        } footer: {
            Text("EmailGobbler adds transactions only while the book is closed in GnuCash, and backs it up first.")
        }
    }

    private var spendingSection: some View {
        Section {
            Toggle("Book AmEx purchase alerts", isOn: $editor.draft.gnuCash.amex.enabled)
            if editor.draft.gnuCash.amex.enabled {
                account("American Express account", $editor.draft.gnuCash.amex.account, field: "gnuCash.amex.account")
            }
            Toggle("Book PayPal payment receipts", isOn: $editor.draft.gnuCash.payPal.enabled)
            if editor.draft.gnuCash.payPal.enabled {
                account("PayPal account", $editor.draft.gnuCash.payPal.account, field: "gnuCash.payPal.account")
                account("Paid from bank", $editor.draft.gnuCash.payPal.bankFundingAccount,
                        field: "gnuCash.payPal.bankFundingAccount")
                account("Paid from card", $editor.draft.gnuCash.payPal.cardFundingAccount,
                        field: "gnuCash.payPal.cardFundingAccount")
            }
            Toggle("Book Verizon bills on their Auto Pay date", isOn: $editor.draft.gnuCash.verizon.enabled)
            if editor.draft.gnuCash.verizon.enabled {
                account("Paid from", $editor.draft.gnuCash.verizon.account, field: "gnuCash.verizon.account")
            }
            if editor.draft.gnuCash.amex.enabled || editor.draft.gnuCash.payPal.enabled || editor.draft.gnuCash.verizon.enabled {
                account("New merchants", $editor.draft.gnuCash.holdingAccount, field: "gnuCash.holdingAccount")
            }
        } header: {
            Text("Spending")
        } footer: {
            Text("Each purchase is booked like the merchant's latest transaction in the book. "
                 + "Purchases from new merchants go to the New merchants account for you to recategorize.")
        }
    }

    private func account(_ title: String, _ selection: Binding<String?>, field: String) -> some View {
        AccountRow(title: title, account: selection, names: editor.bookAccounts, issue: editor.issue(field))
    }

    private var scheduleSection: some View {
        Section("Schedule and backups") {
            Stepper("Check mail every \(editor.draft.intervalMinutes) minutes",
                    value: $editor.draft.intervalMinutes, in: 5...240, step: 5)
            if let issue = editor.issue("intervalMinutes") { IssueText(issue) }
            Stepper("Keep \(editor.draft.backupRetention) backups per workbook",
                    value: $editor.draft.backupRetention, in: 1...200)
            if let issue = editor.issue("backupRetention") { IssueText(issue) }
        }
    }

    private var startupSection: some View {
        Section("Startup") {
            Toggle("Launch at login", isOn: Binding(
                get: { editor.loginState == .enabled || editor.loginState == .requiresApproval },
                set: { editor.setLaunchAtLogin($0) }))
                .disabled(!editor.hasValidSavedSettings)
            Text(editor.hasValidSavedSettings ? editor.loginState.explanation : "Save valid settings first.")
                .foregroundStyle(.secondary)
            if editor.loginState == .requiresApproval {
                Button("Open Login Items Settings") { LoginItem.openSystemSettings() }
            }
        }
    }

    private var footer: some View {
        HStack {
            if editor.isChecking {
                ProgressView().controlSize(.small)
                Text("Checking settings…").foregroundStyle(.secondary)
            } else if let message = editor.message {
                Text(message).foregroundStyle(editor.issues.isEmpty ? Color.secondary : Color.red)
            }
            Spacer()
            Button("Save") { editor.save() }
                .keyboardShortcut(.defaultAction)
                .disabled(editor.isChecking)
        }
        .padding()
    }
}

private struct WorkbookRow: View {
    let path: String
    let issue: String?
    let choose: () -> Void

    var body: some View {
        HStack {
            Text("Workbook")
            Spacer()
            Text(path.isEmpty ? "None" : URL(fileURLWithPath: path).lastPathComponent)
                .foregroundStyle(.secondary)
                .help(path)
            Button("Choose…", action: choose)
        }
        if let issue { IssueText(issue) }
    }
}

private struct SheetRow: View {
    @Binding var sheet: String
    let names: [String]?
    let issue: String?

    var body: some View {
        if let names, !names.isEmpty {
            Picker("Sheet", selection: $sheet) {
                if !names.contains(sheet) { Text(sheet.isEmpty ? "Choose a sheet" : sheet).tag(sheet) }
                ForEach(names, id: \.self) { Text($0).tag($0) }
            }
        } else {
            TextField("Sheet", text: $sheet)
        }
        if let issue { IssueText(issue) }
    }
}

private struct AccountRow: View {
    let title: String
    @Binding var account: String?
    let names: [String]
    let issue: String?

    var body: some View {
        if names.isEmpty {
            TextField(title, text: Binding(get: { account ?? "" }, set: { account = $0.isEmpty ? nil : $0 }),
                      prompt: Text("Full account name, such as Expenses:Groceries"))
        } else {
            Picker(title, selection: $account) {
                Text("Choose an account").tag(String?.none)
                if let account, !names.contains(account) { Text(account).tag(String?.some(account)) }
                ForEach(names, id: \.self) { Text($0).tag(String?.some($0)) }
            }
        }
        if let issue { IssueText(issue) }
    }
}

private struct IssueText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.callout).foregroundStyle(.red)
    }
}

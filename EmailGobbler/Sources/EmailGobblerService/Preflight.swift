import EtradeDividends
import Foundation
import EmailGobblerCore
import GnuCashBook
import SchoologyGrades

/// Reads each enabled sheet once and reports problems against its settings
/// field. Sheets whose settings are already invalid are skipped.
public func preflightIssues(_ settings: AppSettings,
                            readSheet: (SheetTarget) throws -> SheetSnapshot,
                            loadBook: (URL) throws -> GnuCashBook = { try GnuCashBookStore(url: $0).load() }) -> [SettingsIssue] {
    let invalid = settings.validate().map(\.field)
    var cache: [SheetTarget: Result<SheetSnapshot, Error>] = [:]
    func check(_ target: SheetTarget, field: String, _ checker: (SheetSnapshot) -> [String]) -> [SettingsIssue] {
        if cache[target] == nil { cache[target] = Result { try readSheet(target) } }
        switch cache[target]! {
        case .failure(let error):
            return [SettingsIssue(field: field, message: "\(target.sheetName): \(error)")]
        case .success(let sheet):
            return checker(sheet).map { SettingsIssue(field: field, message: "\(target.sheetName): \($0)") }
        }
    }

    var issues: [SettingsIssue] = []
    if settings.grades.enabled, !invalid.contains("grades.routes") {
        for (index, route) in settings.grades.routes.enumerated() {
            let prefix = "grades.routes[\(index)]"
            guard !invalid.contains(where: { $0.hasPrefix(prefix) }) else { continue }
            let target = SheetTarget(workbook: URL(fileURLWithPath: route.workbookPath), sheetName: route.sheetName)
            issues += check(target, field: "\(prefix).sheetName", checkGradesSheet)
        }
    }
    if settings.dividends.enabled, !invalid.contains(where: { $0.hasPrefix("dividends.") }),
       let path = settings.dividends.workbookPath {
        let target = SheetTarget(workbook: URL(fileURLWithPath: path), sheetName: settings.dividends.sheetName)
        issues += check(target, field: "dividends.sheetName", checkDividendLedger)
    }
    if let path = settings.gnuCash.bookPath, !invalid.contains("gnuCash.bookPath") {
        let url = URL(fileURLWithPath: path)
        do {
            _ = try loadBook(url)
        } catch {
            issues.append(SettingsIssue(field: "gnuCash.bookPath", message: "\(url.lastPathComponent): \(error)"))
        }
    }
    return issues
}

public enum LoginItemState: Equatable, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound

    public var explanation: String {
        switch self {
        case .enabled: return "Starts when you log in."
        case .requiresApproval: return "Allow EmailGobbler in System Settings › General › Login Items."
        case .notRegistered: return "Does not start at login."
        case .notFound: return "Install the app in /Applications to start it at login."
        }
    }
}

/// Accounts that can hold transactions, by full name, for account pickers.
public func postableAccountNames(_ book: GnuCashBook) -> [String] { [] }

/// One line describing a GnuCash book for the settings window.
public func gnuCashBookSummary(_ book: GnuCashBook, fileName: String) -> String {
    let accounts = book.accounts.filter { $0.type != "ROOT" }
    let postable = accounts.filter { !$0.isPlaceholder }.count
    let currencies = Set(accounts.compactMap { $0.commodity }.filter(\.isCurrency).map(\.id)).sorted()
    let plural = { (count: Int, word: String) in "\(count) \(word)\(count == 1 ? "" : "s")" }
    let currencyText = currencies.isEmpty ? "" : ", in " + currencies.joined(separator: ", ")
    return "\(fileName): \(plural(accounts.count, "account")), \(postable) can hold transactions\(currencyText); "
        + plural(book.transactions.count, "transaction")
}

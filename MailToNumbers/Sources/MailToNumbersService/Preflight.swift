import EtradeDividends
import Foundation
import MailNumbersCore
import SchoologyGrades

/// Reads each enabled sheet once and reports problems against its settings
/// field. Sheets whose settings are already invalid are skipped.
public func preflightIssues(_ settings: AppSettings,
                            readSheet: (SheetTarget) throws -> SheetSnapshot) -> [SettingsIssue] {
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
        case .requiresApproval: return "Allow Email Gobbler in System Settings › General › Login Items."
        case .notRegistered: return "Does not start at login."
        case .notFound: return "Install the app in /Applications to start it at login."
        }
    }
}

import EtradeDividends
import Foundation
import MailNumbersCore
import SchoologyGrades

/// Reads each enabled sheet once and reports problems against its settings field.
public func preflightIssues(_ settings: AppSettings,
                            readSheet: (SheetTarget) throws -> SheetSnapshot) -> [SettingsIssue] { [] }

public enum LoginItemState: Equatable, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound

    public var explanation: String { "" }
}

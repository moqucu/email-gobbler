import EtradeDividends
import Foundation
import MailNumbersCore
import SchoologyGrades

public enum UseCaseID: String, Codable, Sendable, CaseIterable {
    case schoologyGrades = "schoology-grades"
    case etradeDividends = "etrade-dividends"
}

public struct StudentRouteSettings: Codable, Equatable, Sendable {
    public var studentLabel: String
    public var workbookPath: String
    public var sheetName: String

    public init(studentLabel: String, workbookPath: String, sheetName: String) {
        self.studentLabel = studentLabel
        self.workbookPath = workbookPath
        self.sheetName = sheetName
    }
}

public struct GradesSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var subject: String?
    public var routes: [StudentRouteSettings]

    public init(enabled: Bool, subject: String? = nil, routes: [StudentRouteSettings]) {
        self.enabled = enabled
        self.subject = subject
        self.routes = routes
    }
}

public struct DividendsSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var subject: String?
    public var workbookPath: String?
    public var sheetName: String

    public init(enabled: Bool, subject: String? = nil, workbookPath: String?, sheetName: String) {
        self.enabled = enabled
        self.subject = subject
        self.workbookPath = workbookPath
        self.sheetName = sheetName
    }
}

public struct SettingsIssue: Equatable, Sendable {
    public let field: String
    public let message: String

    public init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}

public struct ConfiguredUseCase {
    public let id: UseCaseID
    public let useCase: any MailToNumbersUseCase

    public init(id: UseCaseID, useCase: any MailToNumbersUseCase) {
        self.id = id
        self.useCase = useCase
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var intervalMinutes: Int
    public var backupRetention: Int
    public var grades: GradesSettings
    public var dividends: DividendsSettings

    public init(version: Int = AppSettings.currentVersion, intervalMinutes: Int, backupRetention: Int,
                grades: GradesSettings, dividends: DividendsSettings) {
        self.version = version
        self.intervalMinutes = intervalMinutes
        self.backupRetention = backupRetention
        self.grades = grades
        self.dividends = dividends
    }

    public static var standard: AppSettings {
        AppSettings(intervalMinutes: 0, backupRetention: 0,
                    grades: GradesSettings(enabled: false, routes: []),
                    dividends: DividendsSettings(enabled: false, workbookPath: nil, sheetName: ""))
    }

    public func validate() -> [SettingsIssue] { [] }

    public func configuredUseCases() -> [ConfiguredUseCase] { [] }
}

public enum SettingsStoreError: Error, Equatable, CustomStringConvertible {
    case unsupportedVersion(Int)
    case unreadable(String)

    public var description: String {
        switch self {
        case .unsupportedVersion(let version): return "Settings version \(version) is not supported by this app"
        case .unreadable(let reason): return "Settings could not be read: \(reason)"
        }
    }
}

/// Stores settings as JSON in Application Support, outside the repository.
public struct SettingsStore: Sendable {
    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("settings.json")
    }

    public func load() throws -> AppSettings { throw SettingsStoreError.unreadable("not implemented") }
    public func save(_ settings: AppSettings) throws {}
}

public func backupDirectory(base: URL, useCase: UseCaseID) -> URL { base }

/// Deletes all but the newest `keep` backups of `workbook` in `directory`.
@discardableResult
public func pruneBackups(directory: URL, workbook: URL, keep: Int) throws -> [URL] { [] }

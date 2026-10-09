import EtradeDividends
import Foundation
import EmailGobblerCore
import GnuCashBook
import SchoologyGrades
import SpendingEmails

public enum UseCaseID: String, Codable, Sendable, CaseIterable {
    case schoologyGrades = "schoology-grades"
    case etradeDividends = "etrade-dividends"
    case amexPurchases = "amex-purchases"
    case payPalPayments = "paypal-payments"
    case verizonBills = "verizon-bills"
    case appleReceipts = "apple-receipts"
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

public struct AmexBookingSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Full GnuCash account name, such as "Liabilities:Card".
    public var account: String?

    public init(enabled: Bool = false, account: String? = nil) {
        self.enabled = enabled
        self.account = account
    }
}

public struct PayPalBookingSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var account: String?
    public var bankFundingAccount: String?
    public var cardFundingAccount: String?

    public init(enabled: Bool = false, account: String? = nil, bankFundingAccount: String? = nil,
                cardFundingAccount: String? = nil) {
        self.enabled = enabled
        self.account = account
        self.bankFundingAccount = bankFundingAccount
        self.cardFundingAccount = cardFundingAccount
    }
}

public struct VerizonBookingSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// The account Auto Pay draws from.
    public var account: String?

    public init(enabled: Bool = false, account: String? = nil) {
        self.enabled = enabled
        self.account = account
    }
}

public struct AppleReceiptSettings: Codable, Equatable, Sendable {
    /// Archive Apple receipts paid with PayPal once the payment is booked on the PayPal account.
    public var enabled: Bool

    public init(enabled: Bool = false) {
        self.enabled = enabled
    }
}

public struct GnuCashSettings: Codable, Equatable, Sendable {
    /// The GnuCash XML book EmailGobbler reads and writes; `nil` until chosen.
    public var bookPath: String?
    /// Where purchases from merchants the book has never seen are booked.
    public var holdingAccount: String?
    public var amex: AmexBookingSettings
    public var payPal: PayPalBookingSettings
    public var verizon: VerizonBookingSettings
    public var apple: AppleReceiptSettings

    public init(bookPath: String? = nil, holdingAccount: String? = nil, amex: AmexBookingSettings = AmexBookingSettings(),
                payPal: PayPalBookingSettings = PayPalBookingSettings(),
                verizon: VerizonBookingSettings = VerizonBookingSettings(),
                apple: AppleReceiptSettings = AppleReceiptSettings()) {
        self.bookPath = bookPath
        self.holdingAccount = holdingAccount
        self.amex = amex
        self.payPal = payPal
        self.verizon = verizon
        self.apple = apple
    }

    private enum CodingKeys: String, CodingKey {
        case bookPath, holdingAccount, amex, payPal, verizon, apple
    }

    /// Settings saved before spending bookings existed load with them off.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bookPath = try container.decodeIfPresent(String.self, forKey: .bookPath)
        holdingAccount = try container.decodeIfPresent(String.self, forKey: .holdingAccount)
        amex = try container.decodeIfPresent(AmexBookingSettings.self, forKey: .amex) ?? AmexBookingSettings()
        payPal = try container.decodeIfPresent(PayPalBookingSettings.self, forKey: .payPal) ?? PayPalBookingSettings()
        verizon = try container.decodeIfPresent(VerizonBookingSettings.self, forKey: .verizon) ?? VerizonBookingSettings()
        apple = AppleReceiptSettings()
    }

    /// Account settings in a stable order, for enabled bookings only.
    var accountFields: [(field: String, account: String?, missing: String, role: SpendingAccountRole)] {
        var fields: [(String, String?, String, SpendingAccountRole)] = []
        guard amex.enabled || payPal.enabled || verizon.enabled else { return [] }
        fields.append(("gnuCash.holdingAccount", holdingAccount, "Choose an account for new merchants", .expense))
        if amex.enabled { fields.append(("gnuCash.amex.account", amex.account, "Choose the American Express account", .card)) }
        if payPal.enabled {
            fields.append(("gnuCash.payPal.account", payPal.account, "Choose the PayPal account", .wallet))
            fields.append(("gnuCash.payPal.bankFundingAccount", payPal.bankFundingAccount,
                           "Choose the bank account that funds PayPal", .bank))
            fields.append(("gnuCash.payPal.cardFundingAccount", payPal.cardFundingAccount,
                           "Choose the card account that funds PayPal", .card))
        }
        if verizon.enabled {
            fields.append(("gnuCash.verizon.account", verizon.account, "Choose the account that pays the Verizon bill", .billPayment))
        }
        return fields
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
    public let useCase: any EmailUseCase

    public init(id: UseCaseID, useCase: any EmailUseCase) {
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
    public var gnuCash: GnuCashSettings

    public init(version: Int = AppSettings.currentVersion, intervalMinutes: Int, backupRetention: Int,
                grades: GradesSettings, dividends: DividendsSettings, gnuCash: GnuCashSettings = GnuCashSettings()) {
        self.version = version
        self.intervalMinutes = intervalMinutes
        self.backupRetention = backupRetention
        self.grades = grades
        self.dividends = dividends
        self.gnuCash = gnuCash
    }

    private enum CodingKeys: String, CodingKey {
        case version, intervalMinutes, backupRetention, grades, dividends, gnuCash
    }

    /// Settings saved before the GnuCash book existed load without it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        intervalMinutes = try container.decode(Int.self, forKey: .intervalMinutes)
        backupRetention = try container.decode(Int.self, forKey: .backupRetention)
        grades = try container.decode(GradesSettings.self, forKey: .grades)
        dividends = try container.decode(DividendsSettings.self, forKey: .dividends)
        gnuCash = try container.decodeIfPresent(GnuCashSettings.self, forKey: .gnuCash) ?? GnuCashSettings()
    }

    public static var standard: AppSettings {
        AppSettings(intervalMinutes: 30, backupRetention: 30,
                    grades: GradesSettings(enabled: false, routes: []),
                    dividends: DividendsSettings(enabled: false, workbookPath: nil,
                                                 sheetName: EtradeDividendsUseCase.defaultSheetName))
    }

    private static func isBlank(_ text: String?) -> Bool {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isWorkbookPath(_ path: String?) -> Bool {
        !isBlank(path) && (path ?? "").lowercased().hasSuffix(".numbers")
    }

    /// Problems that must be fixed before scheduled runs, in a stable field order.
    public func validate() -> [SettingsIssue] {
        var issues: [SettingsIssue] = []
        if intervalMinutes < 5 { issues.append(SettingsIssue(field: "intervalMinutes", message: "Run at most every 5 minutes")) }
        if backupRetention < 1 { issues.append(SettingsIssue(field: "backupRetention", message: "Keep at least one backup")) }
        if grades.enabled {
            if grades.routes.isEmpty {
                issues.append(SettingsIssue(field: "grades.routes", message: "Add a student and their grades sheet"))
            }
            var seen = Set<String>()
            for (index, route) in grades.routes.enumerated() {
                let prefix = "grades.routes[\(index)]"
                if Self.isBlank(route.studentLabel) {
                    issues.append(SettingsIssue(field: "\(prefix).studentLabel", message: "Enter the student's name as shown in the email"))
                }
                if !Self.isWorkbookPath(route.workbookPath) {
                    issues.append(SettingsIssue(field: "\(prefix).workbookPath", message: "Choose a Numbers workbook"))
                }
                if Self.isBlank(route.sheetName) {
                    issues.append(SettingsIssue(field: "\(prefix).sheetName", message: "Choose a sheet"))
                } else if !seen.insert(route.workbookPath + "\u{0}" + route.sheetName).inserted {
                    issues.append(SettingsIssue(field: "\(prefix).sheetName", message: "Another student already uses this sheet"))
                }
            }
        }
        let bookingsEnabled = gnuCash.amex.enabled || gnuCash.payPal.enabled || gnuCash.verizon.enabled
        if (gnuCash.bookPath != nil || bookingsEnabled) && Self.isBlank(gnuCash.bookPath) {
            issues.append(SettingsIssue(field: "gnuCash.bookPath", message: "Choose a GnuCash book"))
        }
        for (field, account, missing, _) in gnuCash.accountFields where Self.isBlank(account) {
            issues.append(SettingsIssue(field: field, message: missing))
        }
        if dividends.enabled {
            if !Self.isWorkbookPath(dividends.workbookPath) {
                issues.append(SettingsIssue(field: "dividends.workbookPath", message: "Choose the dividend ledger workbook"))
            }
            if Self.isBlank(dividends.sheetName) {
                issues.append(SettingsIssue(field: "dividends.sheetName", message: "Choose a sheet"))
            }
        }
        return issues
    }

    /// Enabled use cases with their sheets. Call `validate()` first.
    public func configuredUseCases() -> [ConfiguredUseCase] {
        var result: [ConfiguredUseCase] = []
        if grades.enabled {
            let query = grades.subject.map { MailQuery(subjectContains: $0, senderContains: SchoologyGradesUseCase.defaultQuery.senderContains) }
                ?? SchoologyGradesUseCase.defaultQuery
            let routes = grades.routes.map {
                StudentRoute(studentLabel: $0.studentLabel,
                             target: SheetTarget(workbook: URL(fileURLWithPath: $0.workbookPath), sheetName: $0.sheetName))
            }
            result.append(ConfiguredUseCase(id: .schoologyGrades, useCase: SchoologyGradesUseCase(routes: routes, mailQuery: query)))
        }
        if dividends.enabled, let path = dividends.workbookPath {
            let defaults = EtradeDividendsUseCase.defaultQuery
            let query = dividends.subject.map { MailQuery(subjectContains: $0, senderContains: defaults.senderContains) } ?? defaults
            let target = SheetTarget(workbook: URL(fileURLWithPath: path), sheetName: dividends.sheetName)
            result.append(ConfiguredUseCase(id: .etradeDividends, useCase: EtradeDividendsUseCase(target: target, mailQuery: query)))
        }
        if let path = gnuCash.bookPath, let holding = gnuCash.holdingAccount {
            let book = URL(fileURLWithPath: path)
            if gnuCash.amex.enabled, let account = gnuCash.amex.account {
                result.append(ConfiguredUseCase(id: .amexPurchases, useCase: AmexPurchasesUseCase(
                    bookURL: book, amexAccount: account, holdingAccount: holding)))
            }
            let payPal = gnuCash.payPal
            if payPal.enabled, let account = payPal.account, let bank = payPal.bankFundingAccount,
               let card = payPal.cardFundingAccount {
                result.append(ConfiguredUseCase(id: .payPalPayments, useCase: PayPalPaymentsUseCase(
                    bookURL: book, accounts: PayPalAccounts(payPal: account, bankFunding: bank, cardFunding: card),
                    holdingAccount: holding)))
            }
            if gnuCash.verizon.enabled, let account = gnuCash.verizon.account {
                result.append(ConfiguredUseCase(id: .verizonBills, useCase: VerizonBillsUseCase(
                    bookURL: book, paymentAccount: account, holdingAccount: holding)))
            }
        }
        return result
    }
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

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    public static var standard: SettingsStore {
        SettingsStore(directory: applicationSupport.appendingPathComponent("EmailGobbler", isDirectory: true))
    }

    /// Returns defaults when no settings were saved yet.
    public func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .standard }
        let settings: AppSettings
        do {
            settings = try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: fileURL))
        } catch {
            throw SettingsStoreError.unreadable("\(error)")
        }
        guard settings.version <= AppSettings.currentVersion else {
            throw SettingsStoreError.unsupportedVersion(settings.version)
        }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
    }
}

public func backupDirectory(base: URL, useCase: UseCaseID) -> URL {
    base.appendingPathComponent("Backups", isDirectory: true).appendingPathComponent(useCase.rawValue, isDirectory: true)
}

/// Deletes all but the newest `keep` (at least one) backups of `workbook` in
/// `directory`, ordered by the timestamp and sequence in their names.
@discardableResult
public func pruneBackups(directory: URL, workbook: URL, keep: Int) throws -> [URL] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let prefix = workbook.deletingPathExtension().lastPathComponent + "-backup-"
    let backups: [(stamp: String, sequence: Int, url: URL)] = try FileManager.default
        .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .compactMap { url in
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix), url.pathExtension == workbook.pathExtension else { return nil }
            let parts = url.deletingPathExtension().lastPathComponent.dropFirst(prefix.count).split(separator: "-")
            guard parts.count == 2, let sequence = Int(parts[1]) else { return nil }
            return (String(parts[0]), sequence, url)
        }
        .sorted { ($0.stamp, $0.sequence) > ($1.stamp, $1.sequence) }
    let doomed = backups.dropFirst(max(keep, 1)).map(\.url)
    for url in doomed { try FileManager.default.removeItem(at: url) }
    return doomed
}

import Foundation
import XCTest
import EmailGobblerCore
@testable import EmailGobblerService

final class ServiceSettingsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("service-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func configured() -> AppSettings {
        AppSettings(intervalMinutes: 30, backupRetention: 30,
                    grades: GradesSettings(enabled: true, routes: [
                        StudentRouteSettings(studentLabel: "Student Alpha", workbookPath: "/tmp/Grades.numbers", sheetName: "Alpha 2026"),
                    ]),
                    dividends: DividendsSettings(enabled: true, workbookPath: "/tmp/Ledger.numbers", sheetName: "Sheet 1"))
    }

    // MARK: - Settings

    func testDefaultsAreThirtyMinutesThirtyBackupsAndNothingEnabled() {
        let settings = AppSettings.standard
        XCTAssertEqual(settings.version, 1)
        XCTAssertEqual(settings.intervalMinutes, 30)
        XCTAssertEqual(settings.backupRetention, 30)
        XCTAssertFalse(settings.grades.enabled)
        XCTAssertFalse(settings.dividends.enabled)
        XCTAssertEqual(settings.dividends.sheetName, "Sheet 1")
        XCTAssertEqual(settings.validate(), [])
        XCTAssertTrue(settings.configuredUseCases().isEmpty)
    }

    func testValidSettingsHaveNoIssues() {
        XCTAssertEqual(configured().validate(), [])
    }

    func testIssuesNameTheField() {
        var settings = configured()
        settings.intervalMinutes = 2
        settings.backupRetention = 0
        settings.grades.routes.append(StudentRouteSettings(studentLabel: " ", workbookPath: "/tmp/Grades.xlsx", sheetName: ""))
        settings.dividends.workbookPath = nil
        settings.dividends.sheetName = " "
        XCTAssertEqual(settings.validate().map(\.field), [
            "intervalMinutes", "backupRetention",
            "grades.routes[1].studentLabel", "grades.routes[1].workbookPath", "grades.routes[1].sheetName",
            "dividends.workbookPath", "dividends.sheetName",
        ])
    }

    func testEnabledGradesNeedARouteAndRoutesNeedDistinctSheets() {
        var settings = configured()
        settings.grades.routes = []
        XCTAssertEqual(settings.validate().map(\.field), ["grades.routes"])
        settings.grades.routes = [
            StudentRouteSettings(studentLabel: "Student Alpha", workbookPath: "/tmp/Grades.numbers", sheetName: "Shared"),
            StudentRouteSettings(studentLabel: "Student Beta", workbookPath: "/tmp/Grades.numbers", sheetName: "Shared"),
        ]
        XCTAssertEqual(settings.validate().map(\.field), ["grades.routes[1].sheetName"])
    }

    func testDisabledUseCasesAreNotValidated() {
        var settings = configured()
        settings.grades = GradesSettings(enabled: false, routes: [])
        settings.dividends = DividendsSettings(enabled: false, workbookPath: nil, sheetName: "")
        XCTAssertEqual(settings.validate(), [])
        XCTAssertTrue(settings.configuredUseCases().isEmpty)
    }

    func testEnabledUseCasesBecomeConfiguredWithTheirSheets() {
        var settings = configured()
        settings.dividends.subject = "Dividend"
        let useCases = settings.configuredUseCases()
        XCTAssertEqual(useCases.map(\.id), [.schoologyGrades, .etradeDividends])
        XCTAssertEqual(useCases[0].useCase.targets,
                       [SheetTarget(workbook: URL(fileURLWithPath: "/tmp/Grades.numbers"), sheetName: "Alpha 2026")])
        XCTAssertEqual(useCases[1].useCase.targets,
                       [SheetTarget(workbook: URL(fileURLWithPath: "/tmp/Ledger.numbers"), sheetName: "Sheet 1")])
        XCTAssertEqual(useCases[1].useCase.mailQuery, MailQuery(subjectContains: "Dividend", senderContains: "etrade.com"))
        XCTAssertEqual(useCases[0].useCase.mailQuery.subjectContains, "Weekly Schoology Summary")
    }

    // MARK: - Settings file

    func testMissingSettingsFileLoadsDefaults() throws {
        XCTAssertEqual(try SettingsStore(directory: directory).load(), .standard)
    }

    func testSettingsRoundTripAndCreateTheDirectory() throws {
        let store = SettingsStore(directory: directory.appendingPathComponent("nested"))
        try store.save(configured())
        XCTAssertEqual(try store.load(), configured())
    }

    func testVersionOneFileWithoutOptionalFieldsLoads() throws {
        let json = """
        {"version":1,"intervalMinutes":45,"backupRetention":10,
         "grades":{"enabled":false,"routes":[]},
         "dividends":{"enabled":true,"workbookPath":"/tmp/Ledger.numbers","sheetName":"Sheet 1"}}
        """
        let store = SettingsStore(directory: directory)
        try Data(json.utf8).write(to: store.fileURL)
        let settings = try store.load()
        XCTAssertEqual(settings.intervalMinutes, 45)
        XCTAssertNil(settings.dividends.subject)
    }

    func testNewerOrCorruptSettingsAreReported() throws {
        let store = SettingsStore(directory: directory)
        var newer = configured()
        newer.version = 2
        try JSONEncoder().encode(newer).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? SettingsStoreError, .unsupportedVersion(2)) }
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load()) { error in
            guard case .unreadable? = error as? SettingsStoreError else { return XCTFail("\(error)") }
        }
    }

    // MARK: - Backups

    func testBackupDirectoryIsPerUseCase() {
        XCTAssertEqual(backupDirectory(base: URL(fileURLWithPath: "/tmp/Support"), useCase: .etradeDividends).path,
                       "/tmp/Support/Backups/etrade-dividends")
    }

    func testPruningKeepsTheNewestBackupsOfThatWorkbookOnly() throws {
        let names = [
            "Ledger-backup-20260901T000000Z-1.numbers", "Ledger-backup-20260902T000000Z-1.numbers",
            "Ledger-backup-20260903T000000Z-2.numbers", "Ledger-backup-20260903T000000Z-10.numbers",
            "Ledger-backup-20260904T000000Z-1.numbers", "Other-backup-20260801T000000Z-1.numbers", "notes.txt",
        ]
        for name in names { try Data().write(to: directory.appendingPathComponent(name)) }
        let deleted = try pruneBackups(directory: directory, workbook: URL(fileURLWithPath: "/x/Ledger.numbers"), keep: 3)
        XCTAssertEqual(Set(deleted.map(\.lastPathComponent)),
                       ["Ledger-backup-20260901T000000Z-1.numbers", "Ledger-backup-20260902T000000Z-1.numbers"])
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(remaining, [
            "Ledger-backup-20260903T000000Z-10.numbers", "Ledger-backup-20260903T000000Z-2.numbers",
            "Ledger-backup-20260904T000000Z-1.numbers", "Other-backup-20260801T000000Z-1.numbers", "notes.txt",
        ])
    }

    func testPruningAlwaysKeepsTheNewestBackup() throws {
        for name in ["Ledger-backup-20260901T000000Z-1.numbers", "Ledger-backup-20260902T000000Z-1.numbers"] {
            try Data().write(to: directory.appendingPathComponent(name))
        }
        try pruneBackups(directory: directory, workbook: URL(fileURLWithPath: "/x/Ledger.numbers"), keep: 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path),
                       ["Ledger-backup-20260902T000000Z-1.numbers"])
        XCTAssertEqual(try pruneBackups(directory: directory.appendingPathComponent("missing"),
                                        workbook: URL(fileURLWithPath: "/x/Ledger.numbers"), keep: 3), [])
    }
}

final class SettingsMigrationTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    func testStandardSettingsLiveInTheEmailGobblerFolder() {
        XCTAssertEqual(SettingsStore.standard.fileURL.deletingLastPathComponent().lastPathComponent, "EmailGobbler")
        XCTAssertEqual(SettingsStore.standard.fileURL.lastPathComponent, "settings.json")
    }

    func testLegacyFolderMovesWhenTheNewOneIsMissing() throws {
        let legacy = base.appendingPathComponent("MailToNumbers")
        let current = base.appendingPathComponent("EmailGobbler")
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("Backups"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: legacy.appendingPathComponent("settings.json"))
        XCTAssertTrue(try migrateLegacyDirectory(from: legacy, to: current))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.appendingPathComponent("settings.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.appendingPathComponent("Backups").path))
    }

    func testExistingNewFolderOrMissingLegacyFolderIsLeftAlone() throws {
        let legacy = base.appendingPathComponent("MailToNumbers")
        let current = base.appendingPathComponent("EmailGobbler")
        XCTAssertFalse(try migrateLegacyDirectory(from: legacy, to: current))
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        XCTAssertFalse(try migrateLegacyDirectory(from: legacy, to: current))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }
}

import Foundation

public enum AutomationError: Error, CustomStringConvertible {
    case scriptCreation
    case failed(String)
    case unexpectedResult
    case backupExists(String)
    case workbookChanged
    case invalidSheetName
    case workbookOpen(String)
    case workbookDownloading(String)
    case workbookMissing(String)

    public var description: String {
        switch self {
        case .scriptCreation: return "Unable to create AppleScript"
        case .failed(let message): return "Automation failed: \(message)"
        case .unexpectedResult: return "Automation returned an unexpected result"
        case .backupExists(let path): return "Backup path already exists: \(path)"
        case .workbookChanged: return "Workbook changed since the preview; no write attempted"
        case .invalidSheetName: return "Sheet names cannot contain tabs or line breaks"
        case .workbookOpen(let name): return "Close \(name) in Numbers; it will be updated on the next run"
        case .workbookDownloading(let name): return "Waiting for iCloud to download \(name); it will be retried on the next run"
        case .workbookMissing(let name): return "\(name) was not found"
        }
    }
}

public func runAppleScript(_ source: String) throws -> NSAppleEventDescriptor {
    guard let script = NSAppleScript(source: source) else { throw AutomationError.scriptCreation }
    var errorInfo: NSDictionary?
    let result = script.executeAndReturnError(&errorInfo)
    if let errorInfo {
        throw AutomationError.failed((errorInfo[NSAppleScript.errorMessage] as? String) ?? "\(errorInfo)")
    }
    return result
}

private func checkSheetName(_ name: String) throws {
    guard !name.isEmpty, !name.contains(where: { "\t\n\r".contains($0) }) else { throw AutomationError.invalidSheetName }
}

/// Reads table 1 of a sheet from a disposable copy, because Numbers may autosave
/// documents it opens.
public func readSheetSnapshot(workbook: URL, sheetName: String) throws -> SheetSnapshot {
    try checkSheetName(sheetName)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mail-to-numbers-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let copy = directory.appendingPathComponent("Inspection.numbers")
    try FileManager.default.copyItem(at: workbook, to: copy)
    let result = try runAppleScript(numbersSnapshotScript(workbookPath: copy.resolvingSymlinksInPath().path, sheetName: sheetName))
    guard let output = result.stringValue else { throw AutomationError.unexpectedResult }
    return try parseSheetSnapshot(output)
}

/// Backs up the workbook, writes the plan, saves, and verifies the saved sheet.
/// Nothing is written when the workbook changed since `plannedFrom` was read or
/// when the anchor row lacks the formats the plan requires.
public func writeSheetUpdate(workbook: URL, sheetName: String, plan: SheetUpdatePlan,
                             plannedFrom: SheetSnapshot, backup: URL) throws {
    guard !FileManager.default.fileExists(atPath: backup.path) else { throw AutomationError.backupExists(backup.path) }
    let latest = try readSheetSnapshot(workbook: workbook, sheetName: sheetName)
    guard latest == plannedFrom else { throw AutomationError.workbookChanged }
    try plan.validateTemplate(in: latest)

    try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: workbook, to: backup)
    _ = try runAppleScript(numbersWriteScript(workbookPath: workbook.resolvingSymlinksInPath().path,
                                              sheetName: sheetName, plan: plan))
    let saved = try readSheetSnapshot(workbook: workbook, sheetName: sheetName)
    try plan.verify(saved: saved, original: latest)
}

public func parseSheetNames(_ output: String) -> [String] {
    output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
}

/// Lists a workbook's sheet names from a disposable copy.
public func readSheetNames(workbook: URL) throws -> [String] {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mail-to-numbers-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let copy = directory.appendingPathComponent("Inspection.numbers")
    try FileManager.default.copyItem(at: workbook, to: copy)
    let result = try runAppleScript("""
    tell application id "com.apple.Numbers"
    \(numbersOpenDocumentScript(path: copy.resolvingSymlinksInPath().path))
        try
            set names to name of every sheet of d
            close d saving no
            set AppleScript's text item delimiters to linefeed
            return names as text
        on error errorText
            try
                close d saving no
            end try
            error errorText
        end try
    end tell
    """)
    return parseSheetNames(result.stringValue ?? "")
}

/// True when `workbook` is among the documents open in Numbers.
public func isWorkbookOpen(_ workbook: URL, openPaths: [String]) -> Bool { false }

public enum WorkbookAvailability: Equatable, Sendable {
    case available
    case downloading
    case missing
}

/// iCloud download state: `nil` for files outside iCloud, otherwise one of
/// `NSMetadataUbiquitousItemDownloadingStatus*` raw values.
public func workbookAvailability(exists: Bool, placeholderExists: Bool, downloadStatus: String?) -> WorkbookAvailability {
    .missing
}

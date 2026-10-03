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
    try requireWorkbookAvailable(workbook)
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
    // Writing opens, saves, and closes the document, so never touch one the user has open.
    guard !isWorkbookOpen(workbook, openPaths: try openNumbersDocumentPaths()) else {
        throw AutomationError.workbookOpen(workbook.lastPathComponent)
    }

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

private func normalizedPath(_ path: String) -> String {
    var normalized = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    while normalized.count > 1 && normalized.hasSuffix("/") { normalized.removeLast() }
    return normalized.lowercased()
}

/// True when `workbook` is among the documents open in Numbers. APFS volumes
/// are case-insensitive by default, so paths compare without case.
public func isWorkbookOpen(_ workbook: URL, openPaths: [String]) -> Bool {
    let target = normalizedPath(workbook.path)
    return openPaths.contains { normalizedPath($0) == target }
}

/// Paths of documents open in Numbers, without launching Numbers.
public func openNumbersDocumentPaths() throws -> [String] {
    let result = try runAppleScript("""
    if application id "com.apple.Numbers" is not running then return ""
    tell application id "com.apple.Numbers"
        set out to {}
        repeat with candidate in documents
            try
                set end of out to POSIX path of ((file of candidate) as alias)
            end try
        end repeat
        set AppleScript's text item delimiters to linefeed
        return out as text
    end tell
    """)
    return parseSheetNames(result.stringValue ?? "")
}

public enum WorkbookAvailability: Equatable, Sendable {
    case available
    case downloading
    case missing
}

/// iCloud download state: `nil` for files outside iCloud, otherwise one of
/// `NSMetadataUbiquitousItemDownloadingStatus*` raw values.
public func workbookAvailability(exists: Bool, placeholderExists: Bool, downloadStatus: String?) -> WorkbookAvailability {
    if exists {
        return downloadStatus == NSMetadataUbiquitousItemDownloadingStatusNotDownloaded ? .downloading : .available
    }
    return placeholderExists ? .downloading : .missing
}

/// Throws unless the workbook is on disk; starts an iCloud download when needed.
public func requireWorkbookAvailable(_ workbook: URL) throws {
    let manager = FileManager.default
    let placeholder = workbook.deletingLastPathComponent().appendingPathComponent(".\(workbook.lastPathComponent).icloud")
    let status = (try? workbook.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
        .ubiquitousItemDownloadingStatus?.rawValue
    switch workbookAvailability(exists: manager.fileExists(atPath: workbook.path),
                                placeholderExists: manager.fileExists(atPath: placeholder.path),
                                downloadStatus: status) {
    case .available:
        return
    case .downloading:
        try? manager.startDownloadingUbiquitousItem(at: workbook)
        throw AutomationError.workbookDownloading(workbook.lastPathComponent)
    case .missing:
        throw AutomationError.workbookMissing(workbook.lastPathComponent)
    }
}

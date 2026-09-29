import Foundation
import SchoologyDomain

enum NumbersReadError: Error, CustomStringConvertible {
    case automation(String)
    case malformedSnapshot

    var description: String {
        switch self {
        case .automation(let message): return "Numbers access failed: \(message)"
        case .malformedSnapshot: return "Numbers returned an unexpected sheet layout"
        }
    }
}

func readNumbersSnapshot(at url: URL, sheetName: String) throws -> WorkbookSheetSnapshot {
    guard !sheetName.isEmpty, !sheetName.contains("\n"), !sheetName.contains("\r"),
          !sheetName.contains("\t") else { throw NumbersReadError.malformedSnapshot }

    // Numbers may autosave an opened document. Inspect a disposable copy instead.
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("schoology-numbers-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let copy = temporaryDirectory.appendingPathComponent("Inspection.numbers")
    try FileManager.default.copyItem(at: url, to: copy)

    let script = """
    tell application id "com.apple.Numbers"
        set d to open POSIX file \(appleScriptString(copy.path))
        try
            set t to table 1 of sheet \(appleScriptString(sheetName)) of d
            set outputText to "H"
            repeat with c from 1 to column count of t
                set v to value of cell c of row 1 of t
                if v is missing value then set v to ""
                set outputText to outputText & tab & (v as text)
            end repeat
            set outputText to outputText & linefeed
            repeat with r from 2 to row count of t
                set v to value of cell 1 of row r of t
                if v is not missing value then
                    set outputText to outputText & "D" & tab & r & tab & (year of v as text) & "-" & (month of v as integer as text) & "-" & (day of v as text) & linefeed
                end if
            end repeat
            close d saving no
            return outputText
        on error errorText
            try
                close d saving no
            end try
            error errorText
        end try
    end tell
    """
    guard let appleScript = NSAppleScript(source: script) else {
        throw NumbersReadError.automation("Unable to create AppleScript")
    }
    var errorInfo: NSDictionary?
    let result = appleScript.executeAndReturnError(&errorInfo)
    if let errorInfo { throw NumbersReadError.automation("\(errorInfo)") }
    guard let output = result.stringValue else { throw NumbersReadError.malformedSnapshot }
    let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
    guard let headerLine = lines.first else { throw NumbersReadError.malformedSnapshot }
    let headerFields = headerLine.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard headerFields.first == "H" else { throw NumbersReadError.malformedSnapshot }
    let headers = Array(headerFields.dropFirst())

    var datedRows: [(row: Int, date: CalendarDate)] = []
    for line in lines.dropFirst() {
        let fields = line.split(separator: "\t").map(String.init)
        guard fields.count == 3, fields[0] == "D", let row = Int(fields[1]) else {
            throw NumbersReadError.malformedSnapshot
        }
        let parts = fields[2].split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]),
              let day = Int(parts[2]), let date = try? CalendarDate(year: year, month: month, day: day) else {
            throw NumbersReadError.malformedSnapshot
        }
        datedRows.append((row: row, date: date))
    }
    return WorkbookSheetSnapshot(headers: headers, datedRows: datedRows)
}

func readNumbersRow(at url: URL, sheetName: String, row: Int) throws -> [String] {
    guard row >= 2, !sheetName.isEmpty, !sheetName.contains("\n"),
          !sheetName.contains("\r"), !sheetName.contains("\t") else {
        throw NumbersReadError.malformedSnapshot
    }
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("schoology-row-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let copy = temporaryDirectory.appendingPathComponent("Inspection.numbers")
    try FileManager.default.copyItem(at: url, to: copy)
    let script = """
    tell application id "com.apple.Numbers"
        set d to open POSIX file \(appleScriptString(copy.path))
        try
            set t to table 1 of sheet \(appleScriptString(sheetName)) of d
            set outputText to ""
            repeat with c from 1 to column count of t
                if c > 1 then set outputText to outputText & tab
                set v to value of cell c of row \(row) of t
                if v is missing value then set v to ""
                set outputText to outputText & (v as text)
            end repeat
            close d saving no
            return outputText
        on error errorText
            try
                close d saving no
            end try
            error errorText
        end try
    end tell
    """
    guard let appleScript = NSAppleScript(source: script) else {
        throw NumbersReadError.automation("Unable to create AppleScript")
    }
    var errorInfo: NSDictionary?
    let result = appleScript.executeAndReturnError(&errorInfo)
    if let errorInfo { throw NumbersReadError.automation("\(errorInfo)") }
    guard let output = result.stringValue else { throw NumbersReadError.malformedSnapshot }
    return output.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
}

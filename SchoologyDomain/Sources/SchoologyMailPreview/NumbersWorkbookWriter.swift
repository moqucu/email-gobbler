import Foundation
import SchoologyDomain

enum NumbersWriteError: Error, CustomStringConvertible {
    case backupExists
    case workbookChanged
    case automation(String)
    case verificationFailed(String)

    var description: String {
        switch self {
        case .backupExists: return "Backup path already exists"
        case .workbookChanged: return "Workbook changed since the preview; no write attempted"
        case .automation(let message): return "Numbers write failed: \(message)"
        case .verificationFailed(let message): return "Saved workbook did not verify: \(message)"
        }
    }
}

func writeNumbersUpdate(
    at url: URL,
    sheetName: String,
    snapshot: WorkbookSheetSnapshot,
    plan: WorkbookUpdatePlan,
    backupURL: URL
) throws {
    guard !FileManager.default.fileExists(atPath: backupURL.path) else {
        throw NumbersWriteError.backupExists
    }

    // The plan was made from a read-only copy. Check the source once more before
    // copying it for recovery and opening it in Numbers.
    let latest = try readNumbersSnapshot(at: url, sheetName: sheetName)
    guard latest.headers == snapshot.headers,
          latest.datedRows.map(\.row) == snapshot.datedRows.map(\.row),
          latest.datedRows.map(\.date) == snapshot.datedRows.map(\.date) else {
        throw NumbersWriteError.workbookChanged
    }

    // Numbers scripting cannot set date styles or percentage decimals, so the written
    // row must keep or inherit formatting that the user applied to an existing row.
    let insertion = try rowInsertion(for: plan.action, datedRows: latest.datedRows)
    let template = try readNumbersCellDisplays(at: url, sheetName: sheetName, row: insertion.templateRow)
    try validateTemplateFormats(template, plan: plan, row: insertion.templateRow)

    try FileManager.default.copyItem(at: url, to: backupURL)

    let row: Int
    switch plan.action {
    case .insert(let target), .replace(let target):
        row = target
    }

    let monthNames = ["January", "February", "March", "April", "May", "June",
                      "July", "August", "September", "October", "November", "December"]
    let month = monthNames[plan.weekEnd.month - 1]
    var cellLines: [String] = []
    for cell in plan.cells {
        let value: String
        if let content = cell.value {
            if cell.column.isMultiple(of: 2) {
                guard content.range(of: "^[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil else {
                    throw NumbersWriteError.verificationFailed("invalid planned percentage")
                }
                value = content
            } else {
                value = appleScriptString(content)
            }
        } else {
            value = "missing value"
        }
        cellLines.append("set value of cell \(cell.column) of row \(row) of t to \(value)")
    }
    let script = """
    tell application id "com.apple.Numbers"
        set d to open POSIX file \(appleScriptString(url.path))
        try
            set t to table 1 of sheet \(appleScriptString(sheetName)) of d
            \(insertion.command)
            set targetDate to current date
            set day of targetDate to 1
            set year of targetDate to \(plan.weekEnd.year)
            set month of targetDate to \(month)
            set day of targetDate to \(plan.weekEnd.day)
            set time of targetDate to 0
            set value of cell 1 of row \(row) of t to targetDate
            \(cellLines.joined(separator: "\n            "))
            save d
            close d saving no
            return "saved"
        on error errorText
            try
                close d saving no
            end try
            error errorText
        end try
    end tell
    """
    guard let appleScript = NSAppleScript(source: script) else {
        throw NumbersWriteError.automation("Unable to create AppleScript")
    }
    var errorInfo: NSDictionary?
    _ = appleScript.executeAndReturnError(&errorInfo)
    if let errorInfo { throw NumbersWriteError.automation("\(errorInfo)") }

    let saved = try readNumbersSnapshot(at: url, sheetName: sheetName)
    guard saved.datedRows.first(where: { $0.row == row })?.date == plan.weekEnd else {
        throw NumbersWriteError.verificationFailed("date in row \(row)")
    }
    switch plan.action {
    case .insert:
        let expectedOldRows = snapshot.datedRows.map { prior in
            (row: prior.row >= row ? prior.row + 1 : prior.row, date: prior.date)
        }
        let actualOldRows = saved.datedRows.filter { $0.row != row }
        guard actualOldRows.map(\.row) == expectedOldRows.map(\.row),
              actualOldRows.map(\.date) == expectedOldRows.map(\.date) else {
            throw NumbersWriteError.verificationFailed("existing date rows shifted unexpectedly")
        }
    case .replace:
        guard saved.datedRows.map(\.row) == snapshot.datedRows.map(\.row),
              saved.datedRows.map(\.date) == snapshot.datedRows.map(\.date) else {
            throw NumbersWriteError.verificationFailed("existing date rows changed")
        }
    }
    let values = try readNumbersRow(at: url, sheetName: sheetName, row: row)
    for cell in plan.cells {
        guard cell.column <= values.count else {
            throw NumbersWriteError.verificationFailed("column \(cell.column) missing")
        }
        let actual = values[cell.column - 1]
        if let expected = cell.value {
            if cell.column.isMultiple(of: 2) {
                guard let actualDecimal = Decimal(string: actual),
                      let expectedDecimal = Decimal(string: expected),
                      actualDecimal == expectedDecimal else {
                    throw NumbersWriteError.verificationFailed("column \(cell.column)")
                }
            } else if actual != expected {
                throw NumbersWriteError.verificationFailed("column \(cell.column)")
            }
        } else if !actual.isEmpty {
            throw NumbersWriteError.verificationFailed("column \(cell.column) should be blank")
        }
    }
    let shown = try readNumbersCellDisplays(at: url, sheetName: sheetName, row: row)
    try validateWrittenDisplay(shown, plan: plan, row: row)
}

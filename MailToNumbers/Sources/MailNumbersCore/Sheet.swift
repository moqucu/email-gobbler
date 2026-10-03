import Foundation

public enum SheetValue: Equatable {
    case date(CalendarDate)
    case number(Decimal)
    case text(String)
    case empty

    func sameValue(as other: SheetValue) -> Bool {
        if case .number(let a) = self, case .number(let b) = other {
            let difference = a - b
            return difference <= Decimal(string: "0.000000001")! && difference >= Decimal(string: "-0.000000001")!
        }
        return self == other
    }
}

public enum NumbersCellFormat: Equatable {
    case automatic
    case dateAndTime
    case percent
    case currency
    case text
    case other(String)

    public init(appleScriptName: String) {
        switch appleScriptName {
        case "automatic": self = .automatic
        case "date and time": self = .dateAndTime
        case "percent": self = .percent
        case "currency": self = .currency
        case "text": self = .text
        default: self = .other(appleScriptName)
        }
    }
}

public struct SheetCell: Equatable {
    public let value: SheetValue
    public let formatted: String?
    public let format: NumbersCellFormat

    public init(value: SheetValue, formatted: String?, format: NumbersCellFormat) {
        self.value = value
        self.formatted = formatted
        self.format = format
    }
}

/// A Numbers table as read through scripting. `rows[0]` is Numbers row 1 (the header).
public struct SheetSnapshot: Equatable {
    public let rows: [[SheetCell]]

    public init(rows: [[SheetCell]]) { self.rows = rows }

    public var rowCount: Int { rows.count }
    public var columnCount: Int { rows.first?.count ?? 0 }

    public var headers: [String] {
        (rows.first ?? []).map { cell in
            if case .text(let text) = cell.value { return text }
            return cell.formatted ?? ""
        }
    }

    /// One-based Numbers coordinates.
    public func cell(row: Int, column: Int) -> SheetCell? {
        guard row >= 1, row <= rows.count, column >= 1, column <= rows[row - 1].count else { return nil }
        return rows[row - 1][column - 1]
    }
}

public enum DateDisplayStyle: Equatable {
    /// 9/21/26
    case monthDayShortYear
    /// 9/21/2026
    case monthDayFullYear

    public func display(_ date: CalendarDate) -> String {
        switch self {
        case .monthDayShortYear: return "\(date.month)/\(date.day)/" + String(format: "%02d", date.year % 100)
        case .monthDayFullYear: return "\(date.month)/\(date.day)/\(date.year)"
        }
    }

    var pattern: String {
        switch self {
        case .monthDayShortYear: return "^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2}$"
        case .monthDayFullYear: return "^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$"
        }
    }
}

public func currencyDisplay(_ amount: Decimal) -> String {
    var value = amount
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, 2, .plain)
    let negative = rounded < 0
    let magnitude = negative ? -rounded : rounded
    let cents = NSDecimalNumber(decimal: magnitude * 100).int64Value
    var dollars = String(cents / 100)
    var groups: [String] = []
    while dollars.count > 3 {
        groups.insert(String(dollars.suffix(3)), at: 0)
        dollars.removeLast(3)
    }
    groups.insert(dollars, at: 0)
    return (negative ? "-$" : "$") + groups.joined(separator: ",") + "." + String(format: "%02lld", cents % 100)
}

private func matches(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
}

private let posix = Locale(identifier: "en_US_POSIX")

private func parseWholePercent(_ text: String?) -> Decimal? {
    guard let text, matches(text, "^-?[0-9]+%$") else { return nil }
    return Decimal(string: String(text.dropLast()), locale: posix)
}

public enum DisplayExpectation: Equatable {
    case exact(String)
    /// A fraction such as 0.8794 shown as a whole percentage such as "88%".
    case wholePercent(of: Decimal)
    case currency(of: Decimal)

    public func matches(_ shown: String?) -> Bool {
        switch self {
        case .exact(let expected):
            return shown == expected
        case .wholePercent(let fraction):
            guard let percent = parseWholePercent(shown) else { return false }
            let difference = percent - fraction * 100
            return difference <= Decimal(string: "0.5")! && difference >= Decimal(string: "-0.5")!
        case .currency:
            return false
        }
    }
}

/// Formatting the anchor row must already have. Numbers scripting cannot set date
/// styles or decimal places, but rows added beside the anchor inherit its formats.
public enum FormatRequirement: Equatable {
    case dateOnly(DateDisplayStyle)
    case wholePercent
    case currency

    func isSatisfied(by cell: SheetCell) -> Bool {
        let shown = cell.formatted ?? ""
        switch self {
        case .dateOnly(let style):
            return cell.format == .dateAndTime && matches(shown, style.pattern)
        case .wholePercent:
            return cell.format == .percent && (shown.isEmpty || parseWholePercent(shown) != nil)
        case .currency:
            return cell.format == .currency && (shown.isEmpty || matches(shown, "^-?\\$[0-9,]+\\.[0-9]{2}$"))
        }
    }
}

public enum RowPlacement: Equatable {
    case replace(row: Int)
    case insertAbove(row: Int)
    case insertBelow(row: Int)

    /// The existing row that is replaced or whose formatting new rows inherit.
    public var anchorRow: Int {
        switch self {
        case .replace(let row), .insertAbove(let row), .insertBelow(let row): return row
        }
    }

    func targetRows(count: Int) -> [Int] {
        switch self {
        case .replace(let row): return [row]
        case .insertAbove(let row): return (0..<count).map { row + $0 }
        case .insertBelow(let row): return (0..<count).map { row + 1 + $0 }
        }
    }
}

public struct PlannedRow: Equatable {
    /// Keyed by one-based column number.
    public let values: [Int: SheetValue]
    public let displays: [Int: DisplayExpectation]

    public init(values: [Int: SheetValue], displays: [Int: DisplayExpectation]) {
        self.values = values
        self.displays = displays
    }
}

public enum SheetError: Error, Equatable, CustomStringConvertible {
    case invalidPlacement
    case invalidValue(String)
    case templateNotFormatted(row: Int, column: Int)
    case rowCountMismatch(expected: Int, actual: Int)
    case valueMismatch(row: Int, column: Int)
    case displayMismatch(row: Int, column: Int, actual: String?)
    case malformedSnapshot
    case malformedMailListing

    public var description: String {
        switch self {
        case .invalidPlacement: return "The planned rows do not fit the sheet"
        case .invalidValue(let value): return "Cannot write value \(value)"
        case .templateNotFormatted(let row, let column):
            return "Row \(row) column \(column) lacks the required cell format; format it in Numbers before writing"
        case .rowCountMismatch(let expected, let actual):
            return "Saved sheet has \(actual) rows instead of \(expected)"
        case .valueMismatch(let row, let column):
            return "Saved sheet has an unexpected value in row \(row) column \(column)"
        case .displayMismatch(let row, let column, let actual):
            return "Saved row \(row) column \(column) is displayed as \(actual ?? "blank")"
        case .malformedSnapshot: return "Numbers returned an unexpected sheet layout"
        case .malformedMailListing: return "Mail returned an unexpected message listing"
        }
    }
}

public struct SheetUpdatePlan: Equatable {
    public let placement: RowPlacement
    public let rows: [PlannedRow]
    /// Requirements on the anchor row, keyed by one-based column.
    public let templateRequirements: [Int: FormatRequirement]

    public init(placement: RowPlacement, rows: [PlannedRow], templateRequirements: [Int: FormatRequirement]) {
        self.placement = placement
        self.rows = rows
        self.templateRequirements = templateRequirements
    }

    public var isEmpty: Bool { rows.isEmpty }

    public var targetRows: [Int] { placement.targetRows(count: rows.count) }

    private func checkFits(_ snapshot: SheetSnapshot) throws {
        let anchor = placement.anchorRow
        guard anchor >= 2, anchor <= snapshot.rowCount else { throw SheetError.invalidPlacement }
        if case .replace = placement, rows.count != 1 { throw SheetError.invalidPlacement }
        for row in rows {
            guard row.values.keys.allSatisfy({ $0 >= 1 && $0 <= snapshot.columnCount }) else {
                throw SheetError.invalidPlacement
            }
        }
    }

    /// The table expected after writing this plan to `snapshot`.
    public func applied(to snapshot: SheetSnapshot) throws -> SheetSnapshot {
        guard !isEmpty else { return snapshot }
        try checkFits(snapshot)
        var table = snapshot.rows
        switch placement {
        case .replace(let row):
            for (column, value) in rows[0].values {
                table[row - 1][column - 1] = SheetCell(value: value, formatted: nil, format: .automatic)
            }
        case .insertAbove, .insertBelow:
            for (target, planned) in zip(targetRows, rows) {
                let cells = (1...snapshot.columnCount).map { column in
                    SheetCell(value: planned.values[column] ?? .empty, formatted: nil, format: .automatic)
                }
                table.insert(cells, at: target - 1)
            }
        }
        return SheetSnapshot(rows: table)
    }

    public func validateTemplate(in snapshot: SheetSnapshot) throws {
        guard !isEmpty else { return }
        try checkFits(snapshot)
        let anchor = placement.anchorRow
        for (column, requirement) in templateRequirements.sorted(by: { $0.key < $1.key }) {
            guard let cell = snapshot.cell(row: anchor, column: column), requirement.isSatisfied(by: cell) else {
                throw SheetError.templateNotFormatted(row: anchor, column: column)
            }
        }
    }

    /// Checks every value of the saved table, then the displays of the written rows.
    public func verify(saved: SheetSnapshot, original: SheetSnapshot) throws {
        let expected = try applied(to: original)
        guard saved.rowCount == expected.rowCount else {
            throw SheetError.rowCountMismatch(expected: expected.rowCount, actual: saved.rowCount)
        }
        for row in 1...expected.rowCount {
            for column in 1...expected.columnCount {
                guard let want = expected.cell(row: row, column: column) else { continue }
                guard let got = saved.cell(row: row, column: column), got.value.sameValue(as: want.value) else {
                    throw SheetError.valueMismatch(row: row, column: column)
                }
            }
        }
        for (target, planned) in zip(targetRows, rows) {
            for (column, expectation) in planned.displays.sorted(by: { $0.key < $1.key }) {
                let shown = saved.cell(row: target, column: column)?.formatted
                guard expectation.matches(shown) else {
                    throw SheetError.displayMismatch(row: target, column: column, actual: shown)
                }
            }
        }
    }
}

// MARK: - Numbers scripting

private func unescape(_ text: Substring) -> String? {
    var result = ""
    var iterator = text.makeIterator()
    while let character = iterator.next() {
        guard character == "\\" else { result.append(character); continue }
        switch iterator.next() {
        case "t": result.append("\t")
        case "n": result.append("\n")
        case "r": result.append("\r")
        case "\\": result.append("\\")
        default: return nil
        }
    }
    return result
}

/// Parses `numbersSnapshotScript` output: a size line, then one line per cell.
public func parseSheetSnapshot(_ output: String) throws -> SheetSnapshot {
    let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
    guard let sizeLine = lines.first else { throw SheetError.malformedSnapshot }
    let size = sizeLine.split(separator: "\t", omittingEmptySubsequences: false)
    guard size.count == 3, size[0] == "S", let rowCount = Int(size[1]), let columnCount = Int(size[2]),
          rowCount >= 1, columnCount >= 1, lines.count == 1 + rowCount * columnCount else {
        throw SheetError.malformedSnapshot
    }
    var cells = [[SheetCell?]](repeating: [SheetCell?](repeating: nil, count: columnCount), count: rowCount)
    for line in lines.dropFirst() {
        let fields = line.split(separator: "\t", maxSplits: 6, omittingEmptySubsequences: false)
        guard fields.count == 7, let row = Int(fields[0]), let column = Int(fields[1]),
              (1...rowCount).contains(row), (1...columnCount).contains(column),
              cells[row - 1][column - 1] == nil, fields[4] == "+" || fields[4] == "-",
              let payload = unescape(fields[3]), let shown = unescape(fields[5]) else {
            throw SheetError.malformedSnapshot
        }
        let value: SheetValue
        switch fields[2] {
        case "E":
            value = .empty
        case "T":
            value = .text(payload)
        case "N":
            guard matches(payload, "^-?[0-9]+(\\.[0-9]+)?([Ee][+-]?[0-9]+)?$"),
                  let number = Decimal(string: payload, locale: posix) else { throw SheetError.malformedSnapshot }
            value = .number(number)
        case "D":
            let parts = payload.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let date = try? CalendarDate(year: parts[0], month: parts[1], day: parts[2]) else {
                throw SheetError.malformedSnapshot
            }
            value = .date(date)
        default:
            throw SheetError.malformedSnapshot
        }
        cells[row - 1][column - 1] = SheetCell(value: value, formatted: fields[4] == "+" ? shown : nil,
                                               format: NumbersCellFormat(appleScriptName: String(fields[6])))
    }
    return SheetSnapshot(rows: try cells.map { row in
        try row.map { cell in
            guard let cell else { throw SheetError.malformedSnapshot }
            return cell
        }
    })
}

/// Opens a workbook and binds it to `d`. Numbers can return before the document
/// object exists, so the script also waits for a document at the same path.
public func numbersOpenDocumentScript(path: String) -> String {
    """
        set targetPath to \(appleScriptString(path))
        set d to missing value
        try
            set d to open POSIX file \(appleScriptString(path))
        end try
        repeat 60 times
            if d is not missing value then exit repeat
            delay 0.5
            repeat with candidate in documents
                try
                    if POSIX path of ((file of candidate) as alias) is targetPath then
                        set d to contents of candidate
                        exit repeat
                    end if
                end try
            end repeat
        end repeat
        if d is missing value then error "Numbers did not open the workbook"
    """
}

private let escapeHandler = #"""
on escapeField(theText)
    set savedDelimiters to AppleScript's text item delimiters
    set theText to theText as text
    repeat with pair in {{"\\", "\\\\"}, {tab, "\\t"}, {linefeed, "\\n"}, {return, "\\r"}}
        set AppleScript's text item delimiters to item 1 of pair
        set pieces to text items of theText
        set AppleScript's text item delimiters to item 2 of pair
        set theText to pieces as text
    end repeat
    set AppleScript's text item delimiters to savedDelimiters
    return theText
end escapeField

"""#

/// Reads every cell of table 1 of a sheet. Run it on a disposable copy, because
/// Numbers may autosave documents it opens.
public func numbersSnapshotScript(workbookPath: String, sheetName: String) -> String {
    escapeHandler + """
    tell application id "com.apple.Numbers"
    \(numbersOpenDocumentScript(path: workbookPath))
        try
            set t to table 1 of sheet \(appleScriptString(sheetName)) of d
            set rc to row count of t
            set cc to column count of t
            set outLines to {"S" & tab & rc & tab & cc}
            repeat with c from 1 to cc
                set vals to value of every cell of column c of t
                set shownVals to formatted value of every cell of column c of t
                set fmts to format of every cell of column c of t
                repeat with r from 1 to rc
                    set v to item r of vals
                    if v is missing value then
                        set valueKind to "E"
                        set payload to ""
                    else if class of v is date then
                        set valueKind to "D"
                        set payload to ((year of v) as text) & "-" & ((month of v as integer) as text) & "-" & ((day of v) as text)
                    else if class of v is real or class of v is integer then
                        set valueKind to "N"
                        set payload to v as text
                    else
                        set valueKind to "T"
                        set payload to my escapeField(v)
                    end if
                    set shown to item r of shownVals
                    if shown is missing value then
                        set shownField to "-" & tab
                    else
                        set shownField to "+" & tab & my escapeField(shown)
                    end if
                    set end of outLines to (r as text) & tab & (c as text) & tab & valueKind & tab & payload & tab & shownField & tab & ((item r of fmts) as text)
                end repeat
            end repeat
            close d saving no
            set AppleScript's text item delimiters to linefeed
            return outLines as text
        on error errorText
            try
                close d saving no
            end try
            error errorText
        end try
    end tell
    """
}

private let monthNames = ["January", "February", "March", "April", "May", "June",
                          "July", "August", "September", "October", "November", "December"]

private func assignment(_ value: SheetValue, column: Int, row: Int) throws -> [String] {
    let target = "cell \(column) of row \(row) of t"
    switch value {
    case .empty:
        return ["set value of \(target) to missing value"]
    case .text(let text):
        return ["set value of \(target) to \(appleScriptString(text))"]
    case .number(let number):
        let literal = "\(number)"
        guard matches(literal, "^-?[0-9]+(\\.[0-9]+)?$") else { throw SheetError.invalidValue(literal) }
        return ["set value of \(target) to \(literal)"]
    case .date(let date):
        return [
            "set targetDate to current date",
            "set day of targetDate to 1",
            "set year of targetDate to \(date.year)",
            "set month of targetDate to \(monthNames[date.month - 1])",
            "set day of targetDate to \(date.day)",
            "set time of targetDate to 0",
            "set value of \(target) to targetDate",
        ]
    }
}

/// Writes a plan into table 1 of a sheet and saves the workbook.
public func numbersWriteScript(workbookPath: String, sheetName: String, plan: SheetUpdatePlan) throws -> String {
    var lines: [String] = []
    for (index, (target, planned)) in zip(plan.targetRows, plan.rows).enumerated() {
        switch plan.placement {
        case .replace: break
        case .insertAbove(let row): lines.append("add row above row \(row + index) of t")
        case .insertBelow(let row): lines.append("add row below row \(row + index) of t")
        }
        for (column, value) in planned.values.sorted(by: { $0.key < $1.key }) {
            lines += try assignment(value, column: column, row: target)
        }
    }
    return """
    tell application id "com.apple.Numbers"
    \(numbersOpenDocumentScript(path: workbookPath))
        try
            set t to table 1 of sheet \(appleScriptString(sheetName)) of d
            \(lines.joined(separator: "\n            "))
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
}

// MARK: - Mail backlog

public struct MailMessageRef: Equatable {
    public let id: Int32
    public let accountID: String
    public let rfcMessageID: String
    /// Seconds from the listing time back to receipt; more negative is older.
    public let ageOffset: Int

    public init(id: Int32, accountID: String, rfcMessageID: String, ageOffset: Int) {
        self.id = id
        self.accountID = accountID
        self.rfcMessageID = rfcMessageID
        self.ageOffset = ageOffset
    }
}

/// Parses `id<TAB>account<TAB>message-id<TAB>offset` lines into oldest-first order.
public func parseMailListing(_ output: String) throws -> [MailMessageRef] {
    try output.split(separator: "\n", omittingEmptySubsequences: true).map { line in
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count == 4, let id = Int32(fields[0]), id > 0, !fields[1].isEmpty, !fields[2].isEmpty,
              let offset = Int(fields[3]) else { throw SheetError.malformedMailListing }
        return MailMessageRef(id: id, accountID: String(fields[1]), rfcMessageID: String(fields[2]), ageOffset: offset)
    }.sorted { ($0.ageOffset, $0.id) < ($1.ageOffset, $1.id) }
}

/// Runs items in order and stops at the first failure, leaving later items untouched.
public func processInOrder<T>(_ items: [T], _ process: (T) throws -> Void) throws {
    for item in items { try process(item) }
}

// MARK: - Backups

public func backupURL(directory: URL, workbook: URL, timestamp: Date, sequence: Int) -> URL {
    let formatter = DateFormatter()
    formatter.locale = posix
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    let base = workbook.deletingPathExtension().lastPathComponent
    return directory.appendingPathComponent("\(base)-backup-\(formatter.string(from: timestamp))-\(sequence).numbers")
}

import Foundation

public enum SheetValue: Equatable {
    case date(CalendarDate)
    case number(Decimal)
    case text(String)
    case empty
}

public enum NumbersCellFormat: Equatable {
    case automatic
    case dateAndTime
    case percent
    case currency
    case text
    case other(String)

    public init(appleScriptName: String) { self = .other(appleScriptName) }
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

public struct SheetSnapshot: Equatable {
    public let rows: [[SheetCell]]
    public init(rows: [[SheetCell]]) { self.rows = rows }
    public var rowCount: Int { 0 }
    public var headers: [String] { [] }
}

public enum DateDisplayStyle: Equatable {
    case monthDayShortYear
    case monthDayFullYear
    public func display(_ date: CalendarDate) -> String { "" }
}

public func currencyDisplay(_ amount: Decimal) -> String { "" }

public enum DisplayExpectation: Equatable {
    case exact(String)
    case wholePercent(of: Decimal)
    public func matches(_ shown: String?) -> Bool { false }
}

public enum FormatRequirement: Equatable {
    case dateOnly(DateDisplayStyle)
    case wholePercent
    case currency
}

public enum RowPlacement: Equatable {
    case replace(row: Int)
    case insertAbove(row: Int)
    case insertBelow(row: Int)
    public var anchorRow: Int { 0 }
}

public struct PlannedRow: Equatable {
    public let values: [Int: SheetValue]
    public let displays: [Int: DisplayExpectation]
    public init(values: [Int: SheetValue], displays: [Int: DisplayExpectation]) {
        self.values = values
        self.displays = displays
    }
}

public enum SheetError: Error, Equatable {
    case notImplemented
    case invalidPlacement
    case templateNotFormatted(row: Int, column: Int)
    case rowCountMismatch(expected: Int, actual: Int)
    case valueMismatch(row: Int, column: Int)
    case displayMismatch(row: Int, column: Int, actual: String?)
    case malformedSnapshot
    case malformedMailListing
}

public struct SheetUpdatePlan: Equatable {
    public let placement: RowPlacement
    public let rows: [PlannedRow]
    public let templateRequirements: [Int: FormatRequirement]
    public init(placement: RowPlacement, rows: [PlannedRow], templateRequirements: [Int: FormatRequirement]) {
        self.placement = placement
        self.rows = rows
        self.templateRequirements = templateRequirements
    }
    public var isEmpty: Bool { false }
    public func applied(to snapshot: SheetSnapshot) throws -> SheetSnapshot { throw SheetError.notImplemented }
    public func validateTemplate(in snapshot: SheetSnapshot) throws { throw SheetError.notImplemented }
    public func verify(saved: SheetSnapshot, original: SheetSnapshot) throws { throw SheetError.notImplemented }
}

public func parseSheetSnapshot(_ output: String) throws -> SheetSnapshot { throw SheetError.notImplemented }
public func numbersOpenDocumentScript(path: String) -> String { "" }
public func numbersSnapshotScript(workbookPath: String, sheetName: String) -> String { "" }
public func numbersWriteScript(workbookPath: String, sheetName: String, plan: SheetUpdatePlan) throws -> String { throw SheetError.notImplemented }

public struct MailMessageRef: Equatable {
    public let id: Int32
    public let accountID: String
    public let rfcMessageID: String
    public let ageOffset: Int
    public init(id: Int32, accountID: String, rfcMessageID: String, ageOffset: Int) {
        self.id = id
        self.accountID = accountID
        self.rfcMessageID = rfcMessageID
        self.ageOffset = ageOffset
    }
}

public func parseMailListing(_ output: String) throws -> [MailMessageRef] { throw SheetError.notImplemented }
public func processInOrder<T>(_ items: [T], _ process: (T) throws -> Void) throws {}
public func backupURL(directory: URL, workbook: URL, timestamp: Date, sequence: Int) -> URL { directory }

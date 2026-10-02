import Foundation
import SchoologyDomain

enum NumbersCellFormat: Equatable {
    case automatic
    case dateAndTime
    case percent
    case other(String)

    init(appleScriptName: String) {
        switch appleScriptName {
        case "automatic": self = .automatic
        case "date and time": self = .dateAndTime
        case "percent": self = .percent
        default: self = .other(appleScriptName)
        }
    }
}

struct NumbersCellDisplay: Equatable {
    let format: NumbersCellFormat
    let formattedValue: String?
}

struct RowInsertion: Equatable {
    let command: String
    let templateRow: Int
}

enum NumbersFormatError: Error, Equatable, CustomStringConvertible {
    case noTemplateRow
    case dateNotFormatted(row: Int)
    case percentageNotFormatted(row: Int, column: Int)
    case writtenDateDisplay(row: Int, expected: String, actual: String?)
    case writtenPercentageDisplay(row: Int, column: Int, actual: String?)

    var description: String {
        switch self {
        case .noTemplateRow:
            return "The sheet has no dated row to copy date and percentage formatting from; enter the first week manually"
        case .dateNotFormatted(let row):
            return "Row \(row) Date cell must use a date-only Date & Time format such as 9/21/26"
        case .percentageNotFormatted(let row, let column):
            return "Row \(row) column \(column) must use the Percentage format with 0 decimal places"
        case .writtenDateDisplay(let row, let expected, let actual):
            return "Saved row \(row) shows date \(actual ?? "blank") instead of \(expected)"
        case .writtenPercentageDisplay(let row, let column, let actual):
            return "Saved row \(row) column \(column) shows \(actual ?? "blank") instead of a whole percentage"
        }
    }
}

func expectedDateDisplay(_ date: CalendarDate) -> String {
    "\(date.month)/\(date.day)/" + String(format: "%02d", date.year % 100)
}

/// Numbers copies explicit cell formats into a row added next to an existing row,
/// so a new week is always inserted beside a dated row whose formatting it inherits.
func rowInsertion(for action: WorkbookUpdatePlan.Action, datedRows: [(row: Int, date: CalendarDate)]) throws -> RowInsertion {
    switch action {
    case .replace(let row):
        return RowInsertion(command: "", templateRow: row)
    case .insert(let row):
        if datedRows.contains(where: { $0.row == row }) {
            return RowInsertion(command: "add row above row \(row) of t", templateRow: row)
        }
        if datedRows.contains(where: { $0.row == row - 1 }) {
            return RowInsertion(command: "add row below row \(row - 1) of t", templateRow: row - 1)
        }
        throw NumbersFormatError.noTemplateRow
    }
}

private func isDateOnly(_ text: String?) -> Bool {
    guard let text else { return false }
    return text.range(of: "^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2}$", options: .regularExpression) != nil
}

private func wholePercent(_ text: String?) -> Decimal? {
    guard let text, text.range(of: "^-?[0-9]+%$", options: .regularExpression) != nil else { return nil }
    return Decimal(string: String(text.dropLast()), locale: Locale(identifier: "en_US_POSIX"))
}

private func percentageColumns(_ plan: WorkbookUpdatePlan) -> [PlannedCell] {
    plan.cells.filter { $0.column.isMultiple(of: 2) }
}

func validateTemplateFormats(_ cells: [NumbersCellDisplay], plan: WorkbookUpdatePlan, row: Int) throws {
    guard let dateCell = cells.first, dateCell.format == .dateAndTime, isDateOnly(dateCell.formattedValue) else {
        throw NumbersFormatError.dateNotFormatted(row: row)
    }
    for planned in percentageColumns(plan) {
        guard planned.column <= cells.count else {
            throw NumbersFormatError.percentageNotFormatted(row: row, column: planned.column)
        }
        let cell = cells[planned.column - 1]
        let shown = cell.formattedValue ?? ""
        guard cell.format == .percent, shown.isEmpty || wholePercent(shown) != nil else {
            throw NumbersFormatError.percentageNotFormatted(row: row, column: planned.column)
        }
    }
}

func validateWrittenDisplay(_ cells: [NumbersCellDisplay], plan: WorkbookUpdatePlan, row: Int) throws {
    let expectedDate = expectedDateDisplay(plan.weekEnd)
    guard cells.first?.formattedValue == expectedDate else {
        throw NumbersFormatError.writtenDateDisplay(row: row, expected: expectedDate, actual: cells.first?.formattedValue)
    }
    for planned in percentageColumns(plan) {
        guard let value = planned.value else { continue }
        let actual = planned.column <= cells.count ? cells[planned.column - 1].formattedValue : nil
        guard let fraction = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
              let shown = wholePercent(actual) else {
            throw NumbersFormatError.writtenPercentageDisplay(row: row, column: planned.column, actual: actual)
        }
        let difference = shown - fraction * 100
        guard difference <= Decimal(string: "0.5")!, difference >= Decimal(string: "-0.5")! else {
            throw NumbersFormatError.writtenPercentageDisplay(row: row, column: planned.column, actual: actual)
        }
    }
}

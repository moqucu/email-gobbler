import Foundation
import SchoologyDomain

enum NumbersCellFormat: Equatable {
    case automatic
    case dateAndTime
    case percent
    case other(String)

    init(appleScriptName: String) {
        self = .other(appleScriptName)
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

    var description: String { "not implemented" }
}

func expectedDateDisplay(_ date: CalendarDate) -> String { "" }

func rowInsertion(for action: WorkbookUpdatePlan.Action, datedRows: [(row: Int, date: CalendarDate)]) throws -> RowInsertion {
    throw NumbersFormatError.noTemplateRow
}

func validateTemplateFormats(_ cells: [NumbersCellDisplay], plan: WorkbookUpdatePlan, row: Int) throws {
    throw NumbersFormatError.noTemplateRow
}

func validateWrittenDisplay(_ cells: [NumbersCellDisplay], plan: WorkbookUpdatePlan, row: Int) throws {
    throw NumbersFormatError.noTemplateRow
}

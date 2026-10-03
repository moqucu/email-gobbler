import Foundation
import MailNumbersCore

public enum GradesWorkbookError: Error, Equatable, CustomStringConvertible {
    case studentNotFound(String)
    case invalidHeaders
    case duplicateCourse(String)
    case unmappedGradedCourse(String)
    case missingWorkbookCourse(String)
    case invalidDateRows
    case noTemplateRow

    public var description: String {
        switch self {
        case .studentNotFound(let name): return "Student not found exactly once in email: \(name)"
        case .invalidHeaders: return "Expected Date, then pairs of course and blank letter headers"
        case .duplicateCourse(let name): return "Duplicate course mapping: \(name)"
        case .unmappedGradedCourse(let name): return "Graded email course has no workbook column: \(name)"
        case .missingWorkbookCourse(let name): return "Workbook course absent from email: \(name)"
        case .invalidDateRows: return "Workbook dates must be contiguous from row 2 and newest first"
        case .noTemplateRow: return "The sheet has no dated row to copy formatting from; enter the first week manually"
        }
    }
}

public struct GradesWorkbookPlan: Equatable {
    public let update: SheetUpdatePlan
    public let ignoredMissingCourses: [String]

    public init(update: SheetUpdatePlan, ignoredMissingCourses: [String]) {
        self.update = update
        self.ignoredMissingCourses = ignoredMissingCourses
    }
}

/// Plans one weekly row for a student sheet laid out as Date, then pairs of
/// percentage and letter columns with the course name above the percentage.
public func planGradesWorkbookUpdate(report: SchoologyWeeklyExtraction, studentLabel: String,
                                     sheet: SheetSnapshot) throws -> GradesWorkbookPlan {
    let students = report.students.filter { $0.studentLabel == studentLabel }
    guard students.count == 1, let student = students.first else {
        throw GradesWorkbookError.studentNotFound(studentLabel)
    }
    let headers = sheet.headers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard headers.count >= 3, headers.count % 2 == 1, headers[0] == "Date" else {
        throw GradesWorkbookError.invalidHeaders
    }

    var percentColumns: [String: Int] = [:]
    for index in stride(from: 1, to: headers.count, by: 2) {
        let name = headers[index]
        guard !name.isEmpty, headers[index + 1].isEmpty, percentColumns[name] == nil else {
            throw GradesWorkbookError.invalidHeaders
        }
        percentColumns[name] = index + 1
    }

    var grades: [String: ExtractedOverallGrade] = [:]
    var ignored: [String] = []
    for course in student.courses {
        let label = course.courseLabel
        let base = label.range(of: " - [0-9]+:", options: .regularExpression).map { String(label[..<$0.lowerBound]) } ?? label
        guard percentColumns[base] != nil else {
            if case .present = course.overallGrade { throw GradesWorkbookError.unmappedGradedCourse(label) }
            ignored.append(label)
            continue
        }
        guard grades[base] == nil else { throw GradesWorkbookError.duplicateCourse(base) }
        grades[base] = course.overallGrade
    }

    let weekEnd = report.reportingPeriod.end
    var values: [Int: SheetValue] = [1: .date(weekEnd)]
    var displays: [Int: DisplayExpectation] = [1: .exact(DateDisplayStyle.monthDayShortYear.display(weekEnd))]
    var requirements: [Int: FormatRequirement] = [1: .dateOnly(.monthDayShortYear)]
    for index in stride(from: 1, to: headers.count, by: 2) {
        let percentColumn = index + 1
        guard let grade = grades[headers[index]] else { throw GradesWorkbookError.missingWorkbookCourse(headers[index]) }
        requirements[percentColumn] = .wholePercent
        switch grade {
        case .missing:
            values[percentColumn] = .empty
            values[percentColumn + 1] = .empty
        case .present(let letter, let percentage):
            if let percentage {
                values[percentColumn] = .number(percentage / 100)
                displays[percentColumn] = .wholePercent(of: percentage / 100)
            } else {
                values[percentColumn] = .empty
            }
            values[percentColumn + 1] = .text(letter.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    var datedRows: [(row: Int, date: CalendarDate)] = []
    for row in 2...max(sheet.rowCount, 2) where row <= sheet.rowCount {
        switch sheet.cell(row: row, column: 1)?.value {
        case .date(let date)?: datedRows.append((row, date))
        case .empty?, nil: continue
        default: throw GradesWorkbookError.invalidDateRows
        }
    }
    for (index, dated) in datedRows.enumerated() {
        guard dated.row == index + 2 else { throw GradesWorkbookError.invalidDateRows }
        if index > 0 && datedRows[index - 1].date <= dated.date { throw GradesWorkbookError.invalidDateRows }
    }

    let placement: RowPlacement
    if let existing = datedRows.first(where: { $0.date == weekEnd }) {
        placement = .replace(row: existing.row)
    } else {
        let target = 2 + datedRows.filter { $0.date > weekEnd }.count
        if datedRows.contains(where: { $0.row == target }) {
            placement = .insertAbove(row: target)
        } else if datedRows.contains(where: { $0.row == target - 1 }) {
            placement = .insertBelow(row: target - 1)
        } else {
            throw GradesWorkbookError.noTemplateRow
        }
    }
    return GradesWorkbookPlan(
        update: SheetUpdatePlan(placement: placement, rows: [PlannedRow(values: values, displays: displays)],
                                templateRequirements: requirements),
        ignoredMissingCourses: ignored
    )
}

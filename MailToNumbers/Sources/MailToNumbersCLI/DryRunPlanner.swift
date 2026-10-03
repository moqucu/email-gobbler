import Foundation
import MailNumbersCore
import SchoologyGrades

struct WorkbookSheetSnapshot {
    let headers: [String]
    let datedRows: [(row: Int, date: CalendarDate)]
}

struct PlannedCell: Equatable {
    let column: Int
    let value: String?
}

struct WorkbookUpdatePlan {
    enum Action: Equatable {
        case insert(row: Int)
        case replace(row: Int)
    }

    let action: Action
    let weekEnd: CalendarDate
    let cells: [PlannedCell]
    let ignoredMissingCourses: [String]
}

enum WorkbookPlanError: Error, CustomStringConvertible {
    case studentNotFound(String)
    case invalidHeaders
    case duplicateCourse(String)
    case unmappedGradedCourse(String)
    case missingWorkbookCourse(String)
    case invalidDateRows

    var description: String {
        switch self {
        case .studentNotFound(let name): return "Student not found exactly once in email: \(name)"
        case .invalidHeaders: return "Expected Date, then pairs of course and blank letter headers"
        case .duplicateCourse(let name): return "Duplicate course mapping: \(name)"
        case .unmappedGradedCourse(let name): return "Graded email course has no workbook column: \(name)"
        case .missingWorkbookCourse(let name): return "Workbook course absent from email: \(name)"
        case .invalidDateRows: return "Workbook dates must be unique, contiguous, and newest first"
        }
    }
}

func planWorkbookUpdate(
    report: SchoologyWeeklyExtraction,
    studentLabel: String,
    sheet: WorkbookSheetSnapshot
) throws -> WorkbookUpdatePlan {
    let students = report.students.filter { $0.studentLabel == studentLabel }
    guard students.count == 1, let student = students.first else {
        throw WorkbookPlanError.studentNotFound(studentLabel)
    }
    guard sheet.headers.count >= 3, sheet.headers.count % 2 == 1,
          sheet.headers[0] == "Date" else { throw WorkbookPlanError.invalidHeaders }

    var columns: [String: Int] = [:]
    for column in stride(from: 1, to: sheet.headers.count, by: 2) {
        let name = sheet.headers[column].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, sheet.headers[column + 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              columns[name] == nil else { throw WorkbookPlanError.invalidHeaders }
        columns[name] = column + 1 // Numbers columns are one-based.
    }

    var grades: [String: ExtractedOverallGrade] = [:]
    var ignored: [String] = []
    for course in student.courses {
        let label = course.courseLabel
        let base: String
        if let suffix = label.range(of: " - [0-9]+:", options: .regularExpression) {
            base = String(label[..<suffix.lowerBound])
        } else {
            base = label
        }
        if columns[base] == nil {
            if case .present = course.overallGrade {
                throw WorkbookPlanError.unmappedGradedCourse(label)
            }
            ignored.append(label)
            continue
        }
        guard grades[base] == nil else { throw WorkbookPlanError.duplicateCourse(base) }
        grades[base] = course.overallGrade
    }

    var cells: [PlannedCell] = []
    for column in stride(from: 1, to: sheet.headers.count, by: 2) {
        let name = sheet.headers[column].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let grade = grades[name] else { throw WorkbookPlanError.missingWorkbookCourse(name) }
        switch grade {
        case .missing:
            cells.append(PlannedCell(column: column + 1, value: nil))
            cells.append(PlannedCell(column: column + 2, value: nil))
        case .present(let letter, let percentage):
            cells.append(PlannedCell(column: column + 1, value: percentage.map { "\($0 / 100)" }))
            cells.append(PlannedCell(column: column + 2, value: letter.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }

    for (index, datedRow) in sheet.datedRows.enumerated() {
        guard datedRow.row == index + 2 else { throw WorkbookPlanError.invalidDateRows }
        if index > 0 && sheet.datedRows[index - 1].date <= datedRow.date {
            throw WorkbookPlanError.invalidDateRows
        }
    }

    let weekEnd = report.reportingPeriod.end
    if let existing = sheet.datedRows.first(where: { $0.date == weekEnd }) {
        return WorkbookUpdatePlan(action: .replace(row: existing.row), weekEnd: weekEnd,
                                  cells: cells, ignoredMissingCourses: ignored)
    }
    let newerRows = sheet.datedRows.filter { $0.date > weekEnd }.count
    return WorkbookUpdatePlan(action: .insert(row: 2 + newerRows), weekEnd: weekEnd,
                              cells: cells, ignoredMissingCourses: ignored)
}

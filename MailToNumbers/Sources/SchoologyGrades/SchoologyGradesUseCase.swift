import Foundation
import MailNumbersCore

public enum SchoologyGradesUseCaseError: Error, CustomStringConvertible {
    case studentRequired

    public var description: String { "Updating a grades sheet requires --student" }
}

/// Weekly Schoology summary emails into one student's weekly grades sheet.
public struct SchoologyGradesUseCase: MailToNumbersUseCase {
    public static let defaultQuery = MailQuery(subjectContains: "Weekly Schoology Summary", senderContains: nil)

    public let mailQuery: MailQuery
    public let studentLabel: String?

    public init(studentLabel: String?, mailQuery: MailQuery = defaultQuery) {
        self.studentLabel = studentLabel
        self.mailQuery = mailQuery
    }

    public func summarize(html: String) throws -> [String] {
        let extraction = try parseSchoologyWeeklyEmail(html: html)
        let period = extraction.reportingPeriod
        var lines = ["Reporting period: \(DateDisplayStyle.monthDayFullYear.display(period.start)) to \(DateDisplayStyle.monthDayFullYear.display(period.end))",
                     "Students: \(extraction.students.count)"]
        for student in extraction.students {
            let graded = student.courses.filter {
                if case .present = $0.overallGrade { return true }
                return false
            }.count
            lines.append("\(student.studentLabel): \(student.courses.count) courses, \(graded) graded")
        }
        return lines
    }

    public func plan(html: String, sheet: SheetSnapshot) throws -> UseCasePlan {
        guard let studentLabel else { throw SchoologyGradesUseCaseError.studentRequired }
        let planned = try planGradesWorkbookUpdate(report: try parseSchoologyWeeklyEmail(html: html),
                                                   studentLabel: studentLabel, sheet: sheet)
        return UseCasePlan(update: planned.update,
                           notes: ["Ignored courses without grades: \(planned.ignoredMissingCourses.count)"])
    }
}

import Foundation
import MailNumbersCore

public struct StudentRoute: Equatable, Sendable {
    public let studentLabel: String
    public let target: SheetTarget

    public init(studentLabel: String, target: SheetTarget) {
        self.studentLabel = studentLabel
        self.target = target
    }
}

public enum SchoologyGradesUseCaseError: Error, Equatable, CustomStringConvertible {
    case notImplemented
    case duplicateTarget(SheetTarget)

    public var description: String {
        switch self {
        case .notImplemented: return "Not implemented"
        case .duplicateTarget(let target): return "Two students are routed to the same sheet: \(target)"
        }
    }
}

/// Weekly Schoology summary emails into each routed student's weekly grades sheet.
public struct SchoologyGradesUseCase: MailToNumbersUseCase {
    public static let defaultQuery = MailQuery(subjectContains: "Weekly Schoology Summary", senderContains: nil)

    public let mailQuery: MailQuery
    public let routes: [StudentRoute]

    public init(routes: [StudentRoute], mailQuery: MailQuery = defaultQuery) {
        self.routes = routes
        self.mailQuery = mailQuery
    }

    public var targets: [SheetTarget] { [] }

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

    public func plan(html: String, sheets: [SheetTarget: SheetSnapshot]) throws -> UseCasePlan {
        throw SchoologyGradesUseCaseError.notImplemented
    }
}

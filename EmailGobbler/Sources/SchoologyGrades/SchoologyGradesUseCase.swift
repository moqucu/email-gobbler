import Foundation
import EmailGobblerCore

public struct StudentRoute: Equatable, Sendable {
    public let studentLabel: String
    public let target: SheetTarget

    public init(studentLabel: String, target: SheetTarget) {
        self.studentLabel = studentLabel
        self.target = target
    }
}

public enum SchoologyGradesUseCaseError: Error, Equatable, CustomStringConvertible {
    case duplicateTarget(SheetTarget)

    public var description: String {
        switch self {
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

    public var targets: [SheetTarget] { routes.map(\.target) }

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

    /// Plans each routed student's sheet. Students without a route are ignored.
    public func plan(html: String, sheets: [SheetTarget: SheetSnapshot]) throws -> UseCasePlan {
        var seen = Set<SheetTarget>()
        for route in routes where !seen.insert(route.target).inserted {
            throw SchoologyGradesUseCaseError.duplicateTarget(route.target)
        }
        let extraction = try parseSchoologyWeeklyEmail(html: html)
        var targetPlans: [TargetPlan] = []
        var notes: [String] = []
        for route in routes {
            guard let sheet = sheets[route.target] else { throw WorkflowError.undeclaredTarget }
            let planned = try planGradesWorkbookUpdate(report: extraction, studentLabel: route.studentLabel, sheet: sheet)
            targetPlans.append(TargetPlan(target: route.target, update: planned.update))
            notes.append("\(route.target): ignored courses without grades: \(planned.ignoredMissingCourses.count)")
        }
        let routed = Set(routes.map(\.studentLabel))
        let unrouted = extraction.students.filter { !routed.contains($0.studentLabel) }.count
        if unrouted > 0 { notes.append("Students without a route: \(unrouted)") }
        return UseCasePlan(targets: targetPlans, notes: notes)
    }
}

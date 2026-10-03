import Foundation
import MailNumbersCore

public enum GradesWorkbookError: Error, Equatable {
    case notImplemented
    case studentNotFound(String)
    case invalidHeaders
    case duplicateCourse(String)
    case unmappedGradedCourse(String)
    case missingWorkbookCourse(String)
    case invalidDateRows
    case noTemplateRow
}

public struct GradesWorkbookPlan: Equatable {
    public let update: SheetUpdatePlan
    public let ignoredMissingCourses: [String]

    public init(update: SheetUpdatePlan, ignoredMissingCourses: [String]) {
        self.update = update
        self.ignoredMissingCourses = ignoredMissingCourses
    }
}

public func planGradesWorkbookUpdate(report: SchoologyWeeklyExtraction, studentLabel: String,
                                     sheet: SheetSnapshot) throws -> GradesWorkbookPlan {
    throw GradesWorkbookError.notImplemented
}

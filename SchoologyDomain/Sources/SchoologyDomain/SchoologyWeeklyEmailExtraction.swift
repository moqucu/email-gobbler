import Foundation

// Extraction types are intentionally separate from WeeklyReport: they carry
// unmapped labels, optional context, and missing grades that the domain model rejects.

public struct ReportingPeriod: Hashable {
    public let start: CalendarDate
    public let end: CalendarDate

    public init(start: CalendarDate, end: CalendarDate) {
        self.start = start
        self.end = end
    }
}

public enum MissingGradeMarker: Hashable {
    case dash
    case blank
}

public enum ExtractedOverallGrade: Hashable {
    case present(letter: String, percentage: Decimal?)
    case missing(MissingGradeMarker)
}

public struct ExtractedCourse: Hashable {
    public let courseLabel: String
    public let gradingPeriodText: String?
    public let overallGrade: ExtractedOverallGrade

    public init(courseLabel: String, gradingPeriodText: String?, overallGrade: ExtractedOverallGrade) {
        self.courseLabel = courseLabel
        self.gradingPeriodText = gradingPeriodText
        self.overallGrade = overallGrade
    }
}

public struct ExtractedStudent: Hashable {
    public let studentLabel: String
    public let courses: [ExtractedCourse]

    public init(studentLabel: String, courses: [ExtractedCourse]) {
        self.studentLabel = studentLabel
        self.courses = courses
    }
}

public struct SchoologyWeeklyExtraction: Hashable {
    public let reportingPeriod: ReportingPeriod
    public let students: [ExtractedStudent]

    public init(reportingPeriod: ReportingPeriod, students: [ExtractedStudent]) {
        self.reportingPeriod = reportingPeriod
        self.students = students
    }
}

public enum SchoologyExtractionError: Error, Hashable {
    case notImplemented
    case unsupportedReportStructure
    case missingReportingDates
    case invalidReportingDate(text: String)
    case reversedReportingRange
    case malformedGrade(studentLabel: String, courseLabel: String)
}

public func parseSchoologyWeeklyEmail(html: String) throws -> SchoologyWeeklyExtraction {
    throw SchoologyExtractionError.notImplemented
}

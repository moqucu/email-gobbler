import Foundation

public enum DomainError: Error, Equatable {
    case notImplemented
    case invalidDate
    case validationFailed(String)
}

public struct CalendarDate: Hashable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        // Minimal validation for the stub contract
        guard year > 0, month >= 1, month <= 12, day >= 1, day <= 31 else {
            throw DomainError.invalidDate
        }
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

public struct CourseGrade: Hashable {
    public let courseId: String
    public let percentage: Decimal?
    public let letter: String

    public init(courseId: String, percentage: Decimal?, letter: String) {
        self.courseId = courseId
        self.percentage = percentage
        self.letter = letter
    }
}

public struct WeeklyRow: Hashable {
    public let studentId: String
    public let academicYear: String
    public let weekEnd: CalendarDate
    public let grades: [CourseGrade]

    public init(studentId: String, academicYear: String, weekEnd: CalendarDate, grades: [CourseGrade]) {
        self.studentId = studentId
        self.academicYear = academicYear
        self.weekEnd = weekEnd
        self.grades = grades
    }
}

public struct WeeklyReport: Hashable {
    public let studentId: String
    public let academicYear: String
    public let periodStart: CalendarDate
    public let periodEnd: CalendarDate
    public let grades: [CourseGrade]

    public init(studentId: String, academicYear: String, periodStart: CalendarDate, periodEnd: CalendarDate, grades: [CourseGrade]) {
        self.studentId = studentId
        self.academicYear = academicYear
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.grades = grades
    }
}

public func upsertWeeklyRows(existingRows: [WeeklyRow], report: WeeklyReport) throws -> [WeeklyRow] {
    throw DomainError.notImplemented
}

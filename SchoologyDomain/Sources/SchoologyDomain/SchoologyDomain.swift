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

    private static func isLeapYear(_ year: Int) -> Bool {
        if year % 400 == 0 { return true }
        if year % 100 == 0 { return false }
        return year % 4 == 0
    }

    private static func daysInMonth(_ month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
    }

    public init(year: Int, month: Int, day: Int) throws {
        guard year > 0 else { throw DomainError.invalidDate }
        guard month >= 1 && month <= 12 else { throw DomainError.invalidDate }
        guard day >= 1 && day <= Self.daysInMonth(month, year: year) else { throw DomainError.invalidDate }

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

private func isNonBlank(_ str: String) -> Bool {
    !str.trimmingCharacters(in: .whitespaces).isEmpty
}

private func isValidLetter(_ letter: String) -> Bool {
    let trimmed = letter.trimmingCharacters(in: .whitespaces)
    return !trimmed.isEmpty && trimmed != "-"
}

private func isFiniteDecimal(_ decimal: Decimal?) -> Bool {
    guard let d = decimal else { return true }
    return !d.isNaN && !d.isInfinite
}

public func upsertWeeklyRows(existingRows: [WeeklyRow], report: WeeklyReport) throws -> [WeeklyRow] {
    // Validate report identifiers
    guard isNonBlank(report.studentId) else {
        throw DomainError.validationFailed("Student ID cannot be blank")
    }
    guard isNonBlank(report.academicYear) else {
        throw DomainError.validationFailed("Academic year cannot be blank")
    }

    // Validate report date range
    guard report.periodStart <= report.periodEnd else {
        throw DomainError.validationFailed("Period start must not be after period end")
    }

    // Validate report grades
    guard !report.grades.isEmpty else {
        throw DomainError.validationFailed("Report grades cannot be empty")
    }

    var reportCourseIds = Set<String>()
    for grade in report.grades {
        guard isNonBlank(grade.courseId) else {
            throw DomainError.validationFailed("Course ID cannot be blank")
        }
        guard isValidLetter(grade.letter) else {
            throw DomainError.validationFailed("Letter grade cannot be blank or dash")
        }
        guard isFiniteDecimal(grade.percentage) else {
            throw DomainError.validationFailed("Percentage must be finite or nil")
        }

        guard !reportCourseIds.contains(grade.courseId) else {
            throw DomainError.validationFailed("Duplicate course ID in report")
        }
        reportCourseIds.insert(grade.courseId)
    }

    // Validate existing rows
    var seenWeekEnds = Set<CalendarDate>()
    for existing in existingRows {
        guard existing.studentId == report.studentId else {
            throw DomainError.validationFailed("Existing row student ID mismatch")
        }
        guard existing.academicYear == report.academicYear else {
            throw DomainError.validationFailed("Existing row academic year mismatch")
        }

        guard !seenWeekEnds.contains(existing.weekEnd) else {
            throw DomainError.validationFailed("Duplicate week end date in existing rows")
        }
        seenWeekEnds.insert(existing.weekEnd)

        // Validate existing row course set matches report
        var existingCourseIds = Set<String>()
        for grade in existing.grades {
            guard isNonBlank(grade.courseId) else {
                throw DomainError.validationFailed("Course ID cannot be blank in existing row")
            }
            guard isValidLetter(grade.letter) else {
                throw DomainError.validationFailed("Letter grade cannot be blank or dash in existing row")
            }
            guard isFiniteDecimal(grade.percentage) else {
                throw DomainError.validationFailed("Percentage must be finite or nil in existing row")
            }

            guard !existingCourseIds.contains(grade.courseId) else {
                throw DomainError.validationFailed("Duplicate course ID in existing row")
            }
            existingCourseIds.insert(grade.courseId)
        }

        guard existingCourseIds == reportCourseIds else {
            throw DomainError.validationFailed("Existing row course set does not match report")
        }
    }

    // Build result: replace or insert
    var resultRows: [WeeklyRow] = []
    var foundReplacement = false

    for existing in existingRows {
        if existing.weekEnd == report.periodEnd {
            // Replace this row
            let sortedGrades = report.grades.sorted { $0.courseId < $1.courseId }
            let newRow = WeeklyRow(
                studentId: report.studentId,
                academicYear: report.academicYear,
                weekEnd: report.periodEnd,
                grades: sortedGrades
            )
            resultRows.append(newRow)
            foundReplacement = true
        } else {
            // Keep existing row with sorted grades
            let sortedGrades = existing.grades.sorted { $0.courseId < $1.courseId }
            let sortedRow = WeeklyRow(
                studentId: existing.studentId,
                academicYear: existing.academicYear,
                weekEnd: existing.weekEnd,
                grades: sortedGrades
            )
            resultRows.append(sortedRow)
        }
    }

    // If no replacement, add new row
    if !foundReplacement {
        let sortedGrades = report.grades.sorted { $0.courseId < $1.courseId }
        let newRow = WeeklyRow(
            studentId: report.studentId,
            academicYear: report.academicYear,
            weekEnd: report.periodEnd,
            grades: sortedGrades
        )
        resultRows.append(newRow)
    }

    // Sort by weekEnd descending (newest first)
    resultRows.sort { $0.weekEnd > $1.weekEnd }

    return resultRows
}

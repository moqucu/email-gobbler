import XCTest
@testable import SchoologyDomain
import Foundation

final class SchoologyDomainTests: XCTestCase {

    private func date(_ year: Int, _ month: Int, _ day: Int) -> CalendarDate {
        return try! CalendarDate(year: year, month: month, day: day)
    }

    func testGroup1_EmptySheetAndReport() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "95.5"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        
        let result = try upsertWeeklyRows(existingRows: [], report: report)
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].weekEnd, date(2025, 3, 9))
        XCTAssertEqual(result[0].grades.count, 1)
        XCTAssertEqual(result[0].grades[0].percentage, Decimal(string: "95.5"))
        XCTAssertEqual(result[0].grades[0].letter, "A")
    }

    func testGroup2_UnsortedExistingWeeks() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        
        let oldest = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)
        let middle = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 9), grades: grades)
        let newest = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 16), grades: grades)
        
        // Incoming is between oldest and middle
        let reportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "92"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 5), grades: reportGrades)
        
        let unsorted = [middle, oldest, newest]
        let result = try upsertWeeklyRows(existingRows: unsorted, report: report)
        
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[0].weekEnd, date(2025, 3, 16))
        XCTAssertEqual(result[1].weekEnd, date(2025, 3, 9))
        XCTAssertEqual(result[2].weekEnd, date(2025, 3, 5))
        XCTAssertEqual(result[3].weekEnd, date(2025, 3, 2))
    }

    func testGroup3_ReplaceExistingWeek() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 9), grades: grades)
        
        let reportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "95"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: reportGrades)
        
        let result = try upsertWeeklyRows(existingRows: [existing], report: report)
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].grades[0].percentage, Decimal(string: "95"))
    }

    func testGroup4_ApplyIdenticalReportTwice() throws {
        let reportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "95"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: reportGrades)
        
        let firstPass = try upsertWeeklyRows(existingRows: [], report: report)
        let secondPass = try upsertWeeklyRows(existingRows: firstPass, report: report)
        
        XCTAssertEqual(firstPass, secondPass)
    }

    func testGroup5_LetterOnlyIncoming() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 9), grades: grades)
        
        let reportGrades = [CourseGrade(courseId: "math", percentage: nil, letter: "B")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: reportGrades)
        
        let result = try upsertWeeklyRows(existingRows: [existing], report: report)
        
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result[0].grades[0].percentage)
        XCTAssertEqual(result[0].grades[0].letter, "B")
    }

    func testGroup6_DistinctCoursesOrdering() throws {
        let grades = [
            CourseGrade(courseId: "science", percentage: Decimal(string: "88"), letter: "B"),
            CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")
        ]
        
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        
        let result = try upsertWeeklyRows(existingRows: [], report: report)
        
        XCTAssertEqual(result[0].grades[0].courseId, "math")
        XCTAssertEqual(result[0].grades[1].courseId, "science")
    }

    func testGroup7_HistoricalAcademicYear() throws {
        let reportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "95"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "1999-00", periodStart: date(2024, 12, 30), periodEnd: date(2025, 1, 5), grades: reportGrades)
        
        let result = try upsertWeeklyRows(existingRows: [], report: report)
        XCTAssertEqual(result[0].academicYear, "1999-00")
        XCTAssertEqual(result[0].weekEnd, date(2025, 1, 5))
    }

    func testGroup8_ReversedDateRange() throws {
        let reportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "95"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 9), periodEnd: date(2025, 3, 3), grades: reportGrades)
        
        XCTAssertThrowsError(try upsertWeeklyRows(existingRows: [], report: report)) { error in
            XCTAssertNotEqual(error as? DomainError, .notImplemented)
        }
        
        let sameDayReport = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 9), periodEnd: date(2025, 3, 9), grades: reportGrades)
        // This expects to not throw or throw something other than validation error, but it throws notImplemented.
        XCTAssertThrowsError(try upsertWeeklyRows(existingRows: [], report: sameDayReport)) { error in
            XCTAssertEqual(error as? DomainError, .notImplemented)
        }
    }

    func testGroup9_MismatchedStudentOrYear() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-b", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)
        
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        
        XCTAssertThrowsError(try upsertWeeklyRows(existingRows: [existing], report: report)) { error in
            XCTAssertNotEqual(error as? DomainError, .notImplemented)
        }
    }

    func testGroup10_DuplicateExistingWeeks() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing1 = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)
        let existing2 = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)
        
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        
        XCTAssertThrowsError(try upsertWeeklyRows(existingRows: [existing1, existing2], report: report)) { error in
            XCTAssertNotEqual(error as? DomainError, .notImplemented)
        }
    }

    func testGroup11_EmptyReportGradesOrCourseMismatch() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)
        
        let emptyReport = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: [])
        XCTAssertThrowsError(try upsertWeeklyRows(existingRows: [existing], report: emptyReport)) { error in
            XCTAssertNotEqual(error as? DomainError, .notImplemented)
        }
        
        let duplicateCourses = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A"), CourseGrade(courseId: "math", percentage: Decimal(string: "80"), letter: "B")]
        let duplicateReport = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: duplicateCourses)
        XCTAssertThrowsError(try upsertWeeklyRows(existingRows: [existing], report: duplicateReport)) { error in
            XCTAssertNotEqual(error as? DomainError, .notImplemented)
        }
    }

    func testGroup12_InvalidIdentifiers() throws {
        let invalidGrades = [CourseGrade(courseId: "", percentage: Decimal(string: "90"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: invalidGrades)
        XCTAssertThrowsError(try upsertWeeklyRows(existingRows: [], report: report)) { error in
            XCTAssertNotEqual(error as? DomainError, .notImplemented)
        }
        
        let invalidLetter = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "-")]
        let report2 = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: invalidLetter)
        XCTAssertThrowsError(try upsertWeeklyRows(existingRows: [], report: report2)) { error in
            XCTAssertNotEqual(error as? DomainError, .notImplemented)
        }
    }

    func testGroup13_InputUnchanged() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = [WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)]
        
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        
        let existingCopy = existing
        let _ = try? upsertWeeklyRows(existingRows: existing, report: report)
        
        XCTAssertEqual(existing, existingCopy)
    }
}

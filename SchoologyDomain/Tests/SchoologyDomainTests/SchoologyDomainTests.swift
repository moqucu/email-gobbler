import XCTest
@testable import SchoologyDomain
import Foundation

final class SchoologyDomainTests: XCTestCase {
    
    private func date(_ year: Int, _ month: Int, _ day: Int) -> CalendarDate {
        return try! CalendarDate(year: year, month: month, day: day)
    }

    private func assertValidationError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            if case DomainError.validationFailed(_) = error {
                // Success
            } else if case DomainError.invalidDate = error {
                // Success for date errors
            } else {
                XCTFail("Expected validation error, got \(error)", file: file, line: line)
            }
        }
    }

    // MARK: - Group 1: Empty Sheet
    func testEmptySheet_InsertsRowWithExactPercentageAndLetter() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "95.5"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        
        let result = try upsertWeeklyRows(existingRows: [], report: report)
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].weekEnd, date(2025, 3, 9))
        XCTAssertEqual(result[0].grades.count, 1)
        XCTAssertEqual(result[0].grades[0].percentage, Decimal(string: "95.5"))
        XCTAssertEqual(result[0].grades[0].letter, "A")
    }

    // MARK: - Group 2: Unsorted existing weeks
    private func setupUnsortedExisting() -> ([WeeklyRow], [CourseGrade]) {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let oldest = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)
        let middle = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 9), grades: grades)
        let newest = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 16), grades: grades)
        return ([middle, oldest, newest], grades)
    }

    func testUnsortedExisting_IncomingNewest() throws {
        let (unsorted, grades) = setupUnsortedExisting()
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 17), periodEnd: date(2025, 3, 23), grades: grades)
        let result = try upsertWeeklyRows(existingRows: unsorted, report: report)
        
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result.map { $0.weekEnd }, [date(2025, 3, 23), date(2025, 3, 16), date(2025, 3, 9), date(2025, 3, 2)])
    }

    func testUnsortedExisting_IncomingMiddle() throws {
        let (unsorted, grades) = setupUnsortedExisting()
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 5), grades: grades)
        let result = try upsertWeeklyRows(existingRows: unsorted, report: report)
        
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result.map { $0.weekEnd }, [date(2025, 3, 16), date(2025, 3, 9), date(2025, 3, 5), date(2025, 3, 2)])
    }

    func testUnsortedExisting_IncomingOldest() throws {
        let (unsorted, grades) = setupUnsortedExisting()
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 2, 17), periodEnd: date(2025, 2, 23), grades: grades)
        let result = try upsertWeeklyRows(existingRows: unsorted, report: report)
        
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result.map { $0.weekEnd }, [date(2025, 3, 16), date(2025, 3, 9), date(2025, 3, 2), date(2025, 2, 23)])
    }
    
    func testUnsortedExisting_PreservesOtherWeeksValues() throws {
        let (unsorted, grades) = setupUnsortedExisting()
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 5), grades: grades)
        let result = try upsertWeeklyRows(existingRows: unsorted, report: report)
        XCTAssertEqual(result.first(where: { $0.weekEnd == date(2025, 3, 2) })?.grades, grades)
    }

    // MARK: - Group 3: Replace existing
    func testReplaceExistingWeek_FullGradesRowUnchanged() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 9), grades: grades)
        
        let reportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "95"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: reportGrades)
        
        let result = try upsertWeeklyRows(existingRows: [existing], report: report)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].grades.first?.percentage, Decimal(string: "95"))
    }

    // MARK: - Group 4: Identical report twice
    func testIdenticalReportTwice_EqualOutput() throws {
        let reportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "95"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: reportGrades)
        
        let firstPass = try upsertWeeklyRows(existingRows: [], report: report)
        let secondPass = try upsertWeeklyRows(existingRows: firstPass, report: report)
        
        XCTAssertEqual(firstPass, secondPass)
        XCTAssertEqual(secondPass.count, 1)
    }
    
    func testReplayAfterReplacement() throws {
        let originalGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 9), grades: originalGrades)
        
        let reportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "95"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: reportGrades)
        
        let firstPass = try upsertWeeklyRows(existingRows: [existing], report: report)
        let secondPass = try upsertWeeklyRows(existingRows: firstPass, report: report)
        XCTAssertEqual(firstPass, secondPass)
    }

    // MARK: - Group 5: Letter-only incoming
    func testLetterOnlyIncoming_PercentageNoneRemainsNone() throws {
        let reportGrades = [CourseGrade(courseId: "math", percentage: nil, letter: "B")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: reportGrades)
        let result = try upsertWeeklyRows(existingRows: [], report: report)
        XCTAssertNil(result[0].grades[0].percentage)
    }
    
    func testLetterOnlyIncoming_ClearsExistingPercentage() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 9), grades: grades)
        
        let reportGrades = [CourseGrade(courseId: "math", percentage: nil, letter: "B")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: reportGrades)
        
        let result = try upsertWeeklyRows(existingRows: [existing], report: report)
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result[0].grades[0].percentage)
        XCTAssertEqual(result[0].grades[0].letter, "B")
    }

    // MARK: - Group 6: Distinct courses ordering
    func testDistinctCourses_CanonicalOrderingForNewRows() throws {
        let grades = [
            CourseGrade(courseId: "science", percentage: Decimal(string: "88"), letter: "B"),
            CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")
        ]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        let result = try upsertWeeklyRows(existingRows: [], report: report)
        
        XCTAssertEqual(result[0].grades[0].courseId, "math")
        XCTAssertEqual(result[0].grades[1].courseId, "science")
    }
    
    func testDistinctCourses_CanonicalOrderingForRetainedRows() throws {
        let grades = [
            CourseGrade(courseId: "science", percentage: Decimal(string: "88"), letter: "B"),
            CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")
        ]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)
        let reportGrades = [
            CourseGrade(courseId: "math", percentage: Decimal(string: "92"), letter: "A"),
            CourseGrade(courseId: "science", percentage: Decimal(string: "89"), letter: "B")
        ]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: reportGrades)
        let result = try upsertWeeklyRows(existingRows: [existing], report: report)
        
        let retained = result.first(where: { $0.weekEnd == date(2025, 3, 2) })!
        XCTAssertEqual(retained.grades[0].courseId, "math")
        XCTAssertEqual(retained.grades[1].courseId, "science")
    }

    // MARK: - Group 7: Historical academic year
    func testHistoricalAcademicYear_RetainedVerbatim() throws {
        let reportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "95"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "1999-00", periodStart: date(2024, 12, 30), periodEnd: date(2025, 1, 5), grades: reportGrades)
        
        let result = try upsertWeeklyRows(existingRows: [], report: report)
        XCTAssertEqual(result[0].academicYear, "1999-00")
        XCTAssertEqual(result[0].weekEnd, date(2025, 1, 5))
    }

    // MARK: - Group 8: Date ranges
    func testDateRange_Reversed() throws {
        let reportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "95"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 9), periodEnd: date(2025, 3, 3), grades: reportGrades)
        assertValidationError(try upsertWeeklyRows(existingRows: [], report: report))
    }

    func testDateRange_SameDay() throws {
        let reportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "95"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 9), periodEnd: date(2025, 3, 9), grades: reportGrades)
        let result = try upsertWeeklyRows(existingRows: [], report: report)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].weekEnd, date(2025, 3, 9))
    }

    // MARK: - Group 9: Mismatches
    func testMismatch_Student() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-b", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationError(try upsertWeeklyRows(existingRows: [existing], report: report))
    }
    
    func testMismatch_AcademicYear() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2025-26", weekEnd: date(2025, 3, 2), grades: grades)
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationError(try upsertWeeklyRows(existingRows: [existing], report: report))
    }

    // MARK: - Group 10: Duplicate existing dates
    func testDuplicateExistingDates_Identical() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing1 = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)
        let existing2 = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationError(try upsertWeeklyRows(existingRows: [existing1, existing2], report: report))
    }
    
    func testDuplicateExistingDates_Conflicting() throws {
        let grades1 = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let grades2 = [CourseGrade(courseId: "math", percentage: Decimal(string: "80"), letter: "B")]
        let existing1 = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades1)
        let existing2 = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades2)
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades1)
        assertValidationError(try upsertWeeklyRows(existingRows: [existing1, existing2], report: report))
    }

    // MARK: - Group 11: Course duplicates and mismatches
    func testCourses_EmptyReportGrades() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)
        let emptyReport = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: [])
        assertValidationError(try upsertWeeklyRows(existingRows: [existing], report: emptyReport))
    }
    
    func testCourses_DuplicateInReport() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)
        let duplicateCourses = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A"), CourseGrade(courseId: "math", percentage: Decimal(string: "80"), letter: "B")]
        let duplicateReport = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: duplicateCourses)
        assertValidationError(try upsertWeeklyRows(existingRows: [existing], report: duplicateReport))
    }
    
    func testCourses_DuplicateInExistingRow() throws {
        let duplicateCourses = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A"), CourseGrade(courseId: "math", percentage: Decimal(string: "80"), letter: "B")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: duplicateCourses)
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")])
        assertValidationError(try upsertWeeklyRows(existingRows: [existing], report: report))
    }
    
    func testCourses_MissingInExistingRow() throws {
        let existingGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let reportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A"), CourseGrade(courseId: "science", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: existingGrades)
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: reportGrades)
        assertValidationError(try upsertWeeklyRows(existingRows: [existing], report: report))
    }
    
    func testCourses_ExtraInExistingRow() throws {
        let existingGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A"), CourseGrade(courseId: "science", percentage: Decimal(string: "90"), letter: "A")]
        let reportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: existingGrades)
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: reportGrades)
        assertValidationError(try upsertWeeklyRows(existingRows: [existing], report: report))
    }

    // MARK: - Group 12: Invalid identifiers
    func testInvalidIdentifiers_BlankStudent() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let report = WeeklyReport(studentId: "   ", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationError(try upsertWeeklyRows(existingRows: [], report: report))
    }
    
    func testInvalidIdentifiers_BlankAcademicYear() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationError(try upsertWeeklyRows(existingRows: [], report: report))
    }
    
    func testInvalidIdentifiers_BlankCourseId() throws {
        let grades = [CourseGrade(courseId: " ", percentage: Decimal(string: "90"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationError(try upsertWeeklyRows(existingRows: [], report: report))
    }
    
    func testInvalidIdentifiers_BlankLetter() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "   ")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationError(try upsertWeeklyRows(existingRows: [], report: report))
    }
    
    func testInvalidIdentifiers_DashLetter() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "-")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationError(try upsertWeeklyRows(existingRows: [], report: report))
    }
    
    func testInvalidIdentifiers_DecimalNaN() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal.nan, letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationError(try upsertWeeklyRows(existingRows: [], report: report))
    }
    
    func testInvalidIdentifiers_ZeroVersusNil() throws {
        let grades0 = [CourseGrade(courseId: "math", percentage: Decimal.zero, letter: "A")]
        let report0 = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades0)
        let result = try upsertWeeklyRows(existingRows: [], report: report0)
        XCTAssertEqual(result[0].grades[0].percentage, Decimal.zero)
        XCTAssertNotNil(result[0].grades[0].percentage)
    }

    // MARK: - Group 13: Input unchanged (Immutability)
    func testImmutability_OnSuccess() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = [WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        
        let existingCopy = existing
        let reportCopy = report
        let _ = try upsertWeeklyRows(existingRows: existing, report: report)
        
        XCTAssertEqual(existing, existingCopy)
        XCTAssertEqual(report, reportCopy)
    }
    
    func testImmutability_OnFailure() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = [WeeklyRow(studentId: "student-b", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)] // Student mismatch
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        
        let existingCopy = existing
        let reportCopy = report
        assertValidationError(try upsertWeeklyRows(existingRows: existing, report: report))
        
        XCTAssertEqual(existing, existingCopy)
        XCTAssertEqual(report, reportCopy)
    }

    // MARK: - CalendarDate Tests
    func testCalendarDate_Validations() throws {
        // Valid
        XCTAssertNoThrow(try CalendarDate(year: 2024, month: 2, day: 29))
        XCTAssertNoThrow(try CalendarDate(year: 2000, month: 2, day: 29)) // Century leap year
        
        // Invalid month
        assertValidationError(try CalendarDate(year: 2024, month: 13, day: 1))
        assertValidationError(try CalendarDate(year: 2024, month: 0, day: 1))
        
        // Invalid day (not leap year)
        assertValidationError(try CalendarDate(year: 2023, month: 2, day: 29))
        assertValidationError(try CalendarDate(year: 1900, month: 2, day: 29)) // Century non-leap year
        
        // Invalid day for month
        assertValidationError(try CalendarDate(year: 2024, month: 4, day: 31))
    }
    
    func testCalendarDate_Comparison() throws {
        let older = try CalendarDate(year: 2024, month: 12, day: 31)
        let newer = try CalendarDate(year: 2025, month: 1, day: 1)
        XCTAssertTrue(older < newer)
        XCTAssertFalse(newer < older)
        XCTAssertEqual(older, older)
    }
}

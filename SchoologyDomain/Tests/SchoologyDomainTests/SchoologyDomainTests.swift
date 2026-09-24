import XCTest
@testable import SchoologyDomain
import Foundation

final class SchoologyDomainTests: XCTestCase {
    
    private func date(_ year: Int, _ month: Int, _ day: Int) -> CalendarDate {
        return try! CalendarDate(year: year, month: month, day: day)
    }

    private func assertValidationFailed<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            if case DomainError.validationFailed(_) = error {
                // Success
            } else {
                XCTFail("Expected validationFailed error, got \(error)", file: file, line: line)
            }
        }
    }
    
    private func assertInvalidDate<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            if case DomainError.invalidDate = error {
                // Success
            } else {
                XCTFail("Expected invalidDate error, got \(error)", file: file, line: line)
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
        XCTAssertEqual(result[0].studentId, "student-a")
        XCTAssertEqual(result[0].academicYear, "2024-25")
        XCTAssertEqual(result[0].grades, grades)
    }

    // MARK: - Group 2: Unsorted existing weeks
    private func setupUnsortedExisting() -> ([WeeklyRow], [CourseGrade], [CourseGrade], [CourseGrade]) {
        let gradesOld = [CourseGrade(courseId: "math", percentage: Decimal(string: "80"), letter: "B")]
        let gradesMid = [CourseGrade(courseId: "math", percentage: Decimal(string: "85"), letter: "B")]
        let gradesNew = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        
        let oldest = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: gradesOld)
        let middle = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 9), grades: gradesMid)
        let newest = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 16), grades: gradesNew)
        
        return ([middle, oldest, newest], gradesOld, gradesMid, gradesNew)
    }

    func testUnsortedExisting_IncomingNewest() throws {
        let (unsorted, gradesOld, gradesMid, gradesNew) = setupUnsortedExisting()
        let gradesReport = [CourseGrade(courseId: "math", percentage: Decimal(string: "95"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 17), periodEnd: date(2025, 3, 23), grades: gradesReport)
        
        let result = try upsertWeeklyRows(existingRows: unsorted, report: report)
        
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[0], WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 23), grades: gradesReport))
        XCTAssertEqual(result[1], WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 16), grades: gradesNew))
        XCTAssertEqual(result[2], WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 9), grades: gradesMid))
        XCTAssertEqual(result[3], WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: gradesOld))
    }

    func testUnsortedExisting_IncomingMiddle() throws {
        let (unsorted, gradesOld, gradesMid, gradesNew) = setupUnsortedExisting()
        let gradesReport = [CourseGrade(courseId: "math", percentage: Decimal(string: "82"), letter: "B")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 5), grades: gradesReport)
        
        let result = try upsertWeeklyRows(existingRows: unsorted, report: report)
        
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[0], WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 16), grades: gradesNew))
        XCTAssertEqual(result[1], WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 9), grades: gradesMid))
        XCTAssertEqual(result[2], WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 5), grades: gradesReport))
        XCTAssertEqual(result[3], WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: gradesOld))
    }

    func testUnsortedExisting_IncomingOldest() throws {
        let (unsorted, gradesOld, gradesMid, gradesNew) = setupUnsortedExisting()
        let gradesReport = [CourseGrade(courseId: "math", percentage: Decimal(string: "70"), letter: "C")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 2, 17), periodEnd: date(2025, 2, 23), grades: gradesReport)
        
        let result = try upsertWeeklyRows(existingRows: unsorted, report: report)
        
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[0], WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 16), grades: gradesNew))
        XCTAssertEqual(result[1], WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 9), grades: gradesMid))
        XCTAssertEqual(result[2], WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: gradesOld))
        XCTAssertEqual(result[3], WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 2, 23), grades: gradesReport))
    }

    // MARK: - Group 3: Replace existing
    func testReplaceExistingWeek_FullGradesRowUnchanged() throws {
        let oldGrades = [
            CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A-"),
            CourseGrade(courseId: "science", percentage: Decimal(string: "85"), letter: "B")
        ]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 9), grades: oldGrades)
        
        let newGrades = [
            CourseGrade(courseId: "math", percentage: Decimal(string: "95"), letter: "A"),
            CourseGrade(courseId: "science", percentage: Decimal(string: "70"), letter: "C")
        ]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: newGrades)
        
        let result = try upsertWeeklyRows(existingRows: [existing], report: report)
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 9), grades: newGrades))
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
        XCTAssertEqual(result[0].grades, reportGrades)
    }
    
    func testLetterOnlyIncoming_ClearsExistingPercentage() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 9), grades: grades)
        
        let reportGrades = [CourseGrade(courseId: "math", percentage: nil, letter: "B")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: reportGrades)
        
        let result = try upsertWeeklyRows(existingRows: [existing], report: report)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].grades, reportGrades)
    }

    // MARK: - Group 6: Distinct courses ordering
    func testDistinctCourses_CanonicalOrderingForNewRows() throws {
        let grades = [
            CourseGrade(courseId: "science", percentage: Decimal(string: "88"), letter: "B"),
            CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")
        ]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        let result = try upsertWeeklyRows(existingRows: [], report: report)
        
        XCTAssertEqual(result[0].grades, [
            CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A"),
            CourseGrade(courseId: "science", percentage: Decimal(string: "88"), letter: "B")
        ])
    }
    
    func testDistinctCourses_CanonicalOrderingForRetainedRows() throws {
        let existingGrades = [
            CourseGrade(courseId: "science", percentage: Decimal(string: "88"), letter: "B"),
            CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")
        ]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: existingGrades)
        
        let reportGrades = [
            CourseGrade(courseId: "math", percentage: Decimal(string: "92"), letter: "A"),
            CourseGrade(courseId: "science", percentage: Decimal(string: "89"), letter: "B")
        ]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: reportGrades)
        let result = try upsertWeeklyRows(existingRows: [existing], report: report)
        
        let expectedRetainedGrades = [
            CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A"),
            CourseGrade(courseId: "science", percentage: Decimal(string: "88"), letter: "B")
        ]
        let expectedReportGrades = [
            CourseGrade(courseId: "math", percentage: Decimal(string: "92"), letter: "A"),
            CourseGrade(courseId: "science", percentage: Decimal(string: "89"), letter: "B")
        ]
        
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].grades, expectedReportGrades)
        XCTAssertEqual(result[1].grades, expectedRetainedGrades)
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
        assertValidationFailed(try upsertWeeklyRows(existingRows: [], report: report))
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
        assertValidationFailed(try upsertWeeklyRows(existingRows: [existing], report: report))
    }
    
    func testMismatch_AcademicYear() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2025-26", weekEnd: date(2025, 3, 2), grades: grades)
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [existing], report: report))
    }

    // MARK: - Group 10: Duplicate existing dates
    func testDuplicateExistingDates_Identical() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing1 = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)
        let existing2 = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [existing1, existing2], report: report))
    }
    
    func testDuplicateExistingDates_Conflicting() throws {
        let grades1 = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let grades2 = [CourseGrade(courseId: "math", percentage: Decimal(string: "80"), letter: "B")]
        let existing1 = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades1)
        let existing2 = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades2)
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades1)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [existing1, existing2], report: report))
    }

    // MARK: - Group 11: Course duplicates and mismatches
    func testCourses_EmptyReportGrades() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)
        let emptyReport = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: [])
        assertValidationFailed(try upsertWeeklyRows(existingRows: [existing], report: emptyReport))
    }
    
    func testCourses_DuplicateInReport() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: grades)
        let duplicateCourses = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A"), CourseGrade(courseId: "math", percentage: Decimal(string: "80"), letter: "B")]
        let duplicateReport = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: duplicateCourses)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [existing], report: duplicateReport))
    }
    
    func testCourses_DuplicateInExistingRow() throws {
        let duplicateCourses = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A"), CourseGrade(courseId: "math", percentage: Decimal(string: "80"), letter: "B")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: duplicateCourses)
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")])
        assertValidationFailed(try upsertWeeklyRows(existingRows: [existing], report: report))
    }
    
    func testCourses_MissingInExistingRow() throws {
        let existingGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let reportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A"), CourseGrade(courseId: "science", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: existingGrades)
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: reportGrades)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [existing], report: report))
    }
    
    func testCourses_ExtraInExistingRow() throws {
        let existingGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A"), CourseGrade(courseId: "science", percentage: Decimal(string: "90"), letter: "A")]
        let reportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: existingGrades)
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: reportGrades)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [existing], report: report))
    }

    // MARK: - Group 12: Invalid identifiers (Report values)
    func testInvalidReport_BlankStudent() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let report = WeeklyReport(studentId: "   ", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [], report: report))
    }
    
    func testInvalidReport_BlankAcademicYear() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [], report: report))
    }
    
    func testInvalidReport_BlankCourseId() throws {
        let grades = [CourseGrade(courseId: " ", percentage: Decimal(string: "90"), letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [], report: report))
    }
    
    func testInvalidReport_BlankLetter() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "   ")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [], report: report))
    }
    
    func testInvalidReport_DashLetter() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "-")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [], report: report))
    }
    
    func testInvalidReport_WhitespaceDashLetter() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: " - ")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [], report: report))
    }
    
    func testInvalidReport_DecimalNaN() throws {
        let grades = [CourseGrade(courseId: "math", percentage: Decimal.nan, letter: "A")]
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [], report: report))
    }
    
    func testValidReport_ZeroVersusNil() throws {
        let grades0 = [CourseGrade(courseId: "math", percentage: Decimal.zero, letter: "A")]
        let report0 = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: grades0)
        let result = try upsertWeeklyRows(existingRows: [], report: report0)
        XCTAssertEqual(result[0].grades[0].percentage, Decimal.zero)
        XCTAssertNotNil(result[0].grades[0].percentage)
    }

    // MARK: - Group 12: Invalid identifiers (Existing row values)
    func testInvalidExistingRow_Retained_BlankCourseId() throws {
        let invalidGrades = [CourseGrade(courseId: "   ", percentage: Decimal(string: "90"), letter: "A")]
        let validReportGrades = [CourseGrade(courseId: "   ", percentage: Decimal(string: "95"), letter: "A")] // Course sets must match to avoid courseMismatch masking
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: invalidGrades)
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: validReportGrades)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [existing], report: report))
    }
    
    func testInvalidExistingRow_Retained_BlankLetter() throws {
        let invalidGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: " ")]
        let validReportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "95"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: invalidGrades)
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: validReportGrades)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [existing], report: report))
    }
    
    func testInvalidExistingRow_ReplacementTarget_DashLetter() throws {
        let invalidGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: "-")]
        let validReportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "95"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 9), grades: invalidGrades) // same weekEnd as report -> replacement target
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: validReportGrades)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [existing], report: report))
    }

    func testInvalidExistingRow_ReplacementTarget_WhitespaceDashLetter() throws {
        let invalidGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "90"), letter: " -  ")]
        let validReportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "95"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 9), grades: invalidGrades)
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: validReportGrades)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [existing], report: report))
    }
    
    func testInvalidExistingRow_Retained_DecimalNaN() throws {
        let invalidGrades = [CourseGrade(courseId: "math", percentage: Decimal.nan, letter: "A")]
        let validReportGrades = [CourseGrade(courseId: "math", percentage: Decimal(string: "95"), letter: "A")]
        let existing = WeeklyRow(studentId: "student-a", academicYear: "2024-25", weekEnd: date(2025, 3, 2), grades: invalidGrades)
        let report = WeeklyReport(studentId: "student-a", academicYear: "2024-25", periodStart: date(2025, 3, 3), periodEnd: date(2025, 3, 9), grades: validReportGrades)
        assertValidationFailed(try upsertWeeklyRows(existingRows: [existing], report: report))
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
        assertValidationFailed(try upsertWeeklyRows(existingRows: existing, report: report))
        
        XCTAssertEqual(existing, existingCopy)
        XCTAssertEqual(report, reportCopy)
    }

    // MARK: - CalendarDate Tests
    func testCalendarDate_Validations() throws {
        // Valid
        XCTAssertNoThrow(try CalendarDate(year: 2024, month: 2, day: 29))
        XCTAssertNoThrow(try CalendarDate(year: 2000, month: 2, day: 29)) // Century leap year
        
        // Invalid month
        assertInvalidDate(try CalendarDate(year: 2024, month: 13, day: 1))
        assertInvalidDate(try CalendarDate(year: 2024, month: 0, day: 1))
        
        // Invalid day (not leap year)
        assertInvalidDate(try CalendarDate(year: 2023, month: 2, day: 29))
        assertInvalidDate(try CalendarDate(year: 1900, month: 2, day: 29)) // Century non-leap year
        
        // Invalid day for month
        assertInvalidDate(try CalendarDate(year: 2024, month: 4, day: 31))
    }
    
    func testCalendarDate_Comparison() throws {
        let older = try CalendarDate(year: 2024, month: 12, day: 31)
        let newer = try CalendarDate(year: 2025, month: 1, day: 1)
        XCTAssertTrue(older < newer)
        XCTAssertFalse(newer < older)
        XCTAssertEqual(older, older)
    }
}

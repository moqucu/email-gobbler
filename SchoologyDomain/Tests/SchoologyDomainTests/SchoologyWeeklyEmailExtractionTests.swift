import XCTest
import Foundation
@testable import SchoologyDomain

// SG-02 RED tests. The baseline is the anonymized fixture; every SyntheticDigest or
// baselineVariant input is a CONSTRUCTED edge case, not an observed Schoology format.
final class SchoologyWeeklyEmailExtractionTests: XCTestCase {

    private let gp = SchoologyFixtures.baselineGradingPeriod

    private func date(_ y: Int, _ m: Int, _ d: Int) -> CalendarDate {
        try! CalendarDate(year: y, month: m, day: d)
    }

    private func pct(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func assertExtractionError(
        _ expected: SchoologyExtractionError,
        _ expression: @autoclosure () throws -> SchoologyWeeklyExtraction,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        do {
            let result = try expression()
            XCTFail("Expected \(expected), got a successful extraction: \(result)", file: file, line: line)
        } catch let error as SchoologyExtractionError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected SchoologyExtractionError.\(expected), got \(error)", file: file, line: line)
        }
    }

    private func onlyCourse(_ result: SchoologyWeeklyExtraction, file: StaticString = #filePath, line: UInt = #line) -> ExtractedCourse? {
        guard result.students.count == 1, result.students[0].courses.count == 1 else {
            XCTFail("Expected exactly one student with one course, got \(result.students)", file: file, line: line)
            return nil
        }
        return result.students[0].courses[0]
    }

    // MARK: - Fixture wiring (passes before the parser exists)

    func testFixture_ResourcesLoadAndOracleIsSelfConsistent() throws {
        let html = try SchoologyFixtures.baselineHTML()
        XCTAssertTrue(html.contains(#"<span class="s-parent-digest-date-start">03/02/26</span>"#))
        XCTAssertTrue(html.contains(#"<span class="s-parent-digest-date-end">03/09/26</span>"#))

        let oracle = try SchoologyFixtures.oracle()
        XCTAssertEqual(oracle.fixture, "schoology-weekly.synthetic.html")
        let expected = try oracle.asExtraction()
        XCTAssertEqual(expected.students.map(\.courses.count), [13, 12])

        let grades = expected.students.flatMap(\.courses).map(\.overallGrade)
        XCTAssertEqual(grades.filter { if case .present(_, .some) = $0 { return true }; return false }.count, 9)
        XCTAssertEqual(grades.filter { if case .present(_, nil) = $0 { return true }; return false }.count, 3)
        XCTAssertEqual(grades.filter { $0 == .missing(.dash) }.count, 13)
    }

    // MARK: - 1. Baseline extraction

    func testBaseline_ReportingPeriodIsMarch2To9_2026() throws {
        let result = try parseSchoologyWeeklyEmail(html: try SchoologyFixtures.baselineHTML())
        XCTAssertEqual(result.reportingPeriod, ReportingPeriod(start: date(2026, 3, 2), end: date(2026, 3, 9)))
    }

    func testBaseline_MatchesFixtureOracle() throws {
        let expected = try SchoologyFixtures.oracle().asExtraction()
        let result = try parseSchoologyWeeklyEmail(html: try SchoologyFixtures.baselineHTML())
        XCTAssertEqual(result, expected)
    }

    func testBaseline_StudentsAndCourseLabelsInDocumentOrder() throws {
        let result = try parseSchoologyWeeklyEmail(html: try SchoologyFixtures.baselineHTML())
        XCTAssertEqual(result.students.map(\.studentLabel), ["Student Alpha", "Student Beta"])
        XCTAssertEqual(result.students.first?.courses.map(\.courseLabel),
                       (1...13).map { String(format: "Example Course %02d: Section 1", $0) })
        XCTAssertEqual(result.students.last?.courses.map(\.courseLabel),
                       (1...12).map { String(format: "Example Course %02d: Section 1", $0) })
    }

    func testBaseline_IndependentSpotChecks() throws {
        let result = try parseSchoologyWeeklyEmail(html: try SchoologyFixtures.baselineHTML())
        guard result.students.count == 2 else { return XCTFail("Expected two students, got \(result.students.count)") }
        let alpha = result.students[0].courses
        let beta = result.students[1].courses
        guard alpha.count == 13, beta.count == 12 else { return XCTFail("Unexpected course counts") }

        XCTAssertEqual(alpha[0].overallGrade, .missing(.dash))
        XCTAssertEqual(alpha[2].overallGrade, .present(letter: "B+", percentage: pct("73.17")))
        XCTAssertEqual(alpha[3].overallGrade, .present(letter: "B", percentage: nil))
        XCTAssertEqual(alpha[7].overallGrade, .present(letter: "B", percentage: pct("78.17")))
        XCTAssertEqual(alpha[9].courseLabel, "Example Course 10: Section 1") // source has trailing space
        XCTAssertEqual(beta[1].overallGrade, .present(letter: "A-", percentage: nil))
        XCTAssertEqual(beta[2].overallGrade, .present(letter: "B+", percentage: pct("73.63")))
        XCTAssertEqual(beta[6].overallGrade, .missing(.dash))
        XCTAssertEqual(beta[8].courseLabel, "Example Course 09: Section 1") // source has trailing space
    }

    func testBaseline_GradingPeriodTextPreservedVerbatimIncludingNoBreakSpace() throws {
        let result = try parseSchoologyWeeklyEmail(html: try SchoologyFixtures.baselineHTML())
        let periods = result.students.flatMap(\.courses).map(\.gradingPeriodText)
        XCTAssertEqual(periods.count, 25)
        XCTAssertEqual(Set(periods), [Optional("25-26 T2\u{00A0}(14 Jan - 12 Jun)")])
    }

    func testBaseline_ParsingIsDeterministic() throws {
        let html = try SchoologyFixtures.baselineHTML()
        XCTAssertEqual(try parseSchoologyWeeklyEmail(html: html), try parseSchoologyWeeklyEmail(html: html))
    }

    // MARK: - 2. Student separation

    func testStudentSeparation_IdenticalCourseLabelsKeepSeparateResults() throws {
        let html = SyntheticDigest.document(students: [
            SyntheticDigest.student("Student Gamma", rows: [
                SyntheticDigest.course("Shared Course: Section 1", gradeHTML: SyntheticDigest.overall("A", "91.5%")),
                SyntheticDigest.course("Only Gamma: Section 2", gradeHTML: "C"),
            ]),
            SyntheticDigest.student("Student Delta", rows: [
                SyntheticDigest.course("Shared Course: Section 1", gradeHTML: SyntheticDigest.dash),
            ]),
        ])
        let result = try parseSchoologyWeeklyEmail(html: html)
        XCTAssertEqual(result.students, [
            ExtractedStudent(studentLabel: "Student Gamma", courses: [
                ExtractedCourse(courseLabel: "Shared Course: Section 1", gradingPeriodText: gp, overallGrade: .present(letter: "A", percentage: pct("91.5"))),
                ExtractedCourse(courseLabel: "Only Gamma: Section 2", gradingPeriodText: gp, overallGrade: .present(letter: "C", percentage: nil)),
            ]),
            ExtractedStudent(studentLabel: "Student Delta", courses: [
                ExtractedCourse(courseLabel: "Shared Course: Section 1", gradingPeriodText: gp, overallGrade: .missing(.dash)),
            ]),
        ])
    }

    // MARK: - 3. Overall grades only

    func testOverallOnly_ConflictingAssignmentAttendanceAndActivityGradesIgnored() throws {
        let html = SyntheticDigest.document(students: [
            SyntheticDigest.student("Student Gamma", rows: [
                SyntheticDigest.course(
                    "Example Course 31: Section 1",
                    gradeHTML: SyntheticDigest.dash,
                    attendanceHTML: "88.8%",
                    assignments: [
                        SyntheticDigest.assignment("Example Assignment 31", gradeHTML: SyntheticDigest.overall("A", "99.99%")),
                        SyntheticDigest.assignment("Example Assignment 32", gradeHTML: "2/10"),
                    ]),
                SyntheticDigest.course(
                    "Example Course 32: Section 1",
                    gradeHTML: SyntheticDigest.overall("C", "70.25%"),
                    assignments: [
                        SyntheticDigest.assignment("Example Assignment 33", gradeHTML: SyntheticDigest.overall("F", "12.34%")),
                    ]),
            ], trailing: SyntheticDigest.recentActivity("Student Gamma", gradeHTML: SyntheticDigest.overall("A+", "100%"))),
        ])
        let result = try parseSchoologyWeeklyEmail(html: html)
        XCTAssertEqual(result.students.map(\.studentLabel), ["Student Gamma"])
        XCTAssertEqual(result.students.first?.courses.map(\.overallGrade), [
            .missing(.dash),
            .present(letter: "C", percentage: pct("70.25")),
        ])
    }

    func testOverallOnly_BaselineAssignmentAndActivityGradesDoNotLeak() throws {
        let result = try parseSchoologyWeeklyEmail(html: try SchoologyFixtures.baselineHTML())
        let letters = result.students.flatMap(\.courses).compactMap { course -> String? in
            if case let .present(letter, _) = course.overallGrade { return letter }
            return nil
        }
        XCTAssertFalse(letters.contains("D"), "Assignment/activity grade D leaked into overall grades")
        XCTAssertFalse(letters.contains { $0.contains("/") }, "Assignment score leaked into overall grades")
        XCTAssertEqual(letters.count, 12)
    }

    // MARK: - 4. Grade fidelity

    func testGradeFidelity_DecimalPercentagesAndLettersPreservedExactly() throws {
        let cases: [(String, String, String)] = [
            ("A+", "100%", "100"), ("A-", "98.5%", "98.5"), ("B+", "73.17%", "73.17"),
            ("C-", "0.01%", "0.01"), ("P", "88.125%", "88.125"),
        ]
        let html = SyntheticDigest.document(students: [
            SyntheticDigest.student("Student Gamma", rows: cases.enumerated().map { index, item in
                SyntheticDigest.course("Example Course 4\(index): Section 1", gradeHTML: SyntheticDigest.overall(item.0, item.1))
            }),
        ])
        let result = try parseSchoologyWeeklyEmail(html: html)
        XCTAssertEqual(result.students.first?.courses.map(\.overallGrade),
                       cases.map { .present(letter: $0.0, percentage: pct($0.2)) })
    }

    func testGradeFidelity_LetterOnlyHasNoInferredPercentage() throws {
        let html = SyntheticDigest.document(students: [
            SyntheticDigest.student("Student Gamma", rows: [
                SyntheticDigest.course("Example Course 51: Section 1", gradeHTML: "B"),
            ]),
        ])
        let course = onlyCourse(try parseSchoologyWeeklyEmail(html: html))
        XCTAssertEqual(course?.overallGrade, .present(letter: "B", percentage: nil))
    }

    // MARK: - 5. Missing grades

    func testMissing_DashAndBlankVariantsAreExplicitAndRowsRetained() throws {
        let cells: [(String, ExtractedOverallGrade)] = [
            (SyntheticDigest.dash, .missing(.dash)),
            ("-", .missing(.dash)),
            (" \n - \n ", .missing(.dash)),
            ("", .missing(.blank)),
            (" \n\t ", .missing(.blank)),
            (#"<span class="empty"></span>"#, .missing(.blank)),
        ]
        let html = SyntheticDigest.document(students: [
            SyntheticDigest.student("Student Gamma", rows: cells.enumerated().map { index, cell in
                SyntheticDigest.course("Example Course 6\(index): Section 1", gradeHTML: cell.0)
            }),
        ])
        let result = try parseSchoologyWeeklyEmail(html: html)
        XCTAssertEqual(result.students.first?.courses.map(\.courseLabel),
                       (0..<cells.count).map { "Example Course 6\($0): Section 1" })
        XCTAssertEqual(result.students.first?.courses.map(\.overallGrade), cells.map(\.1))
    }

    func testMissing_DistinguishableFromNumericZero() throws {
        let html = SyntheticDigest.document(students: [
            SyntheticDigest.student("Student Gamma", rows: [
                SyntheticDigest.course("Example Course 71: Section 1", gradeHTML: SyntheticDigest.overall("F", "0%")),
                SyntheticDigest.course("Example Course 72: Section 1", gradeHTML: SyntheticDigest.dash),
                SyntheticDigest.course("Example Course 73: Section 1", gradeHTML: ""),
            ]),
        ])
        let grades = try parseSchoologyWeeklyEmail(html: html).students.first?.courses.map(\.overallGrade)
        XCTAssertEqual(grades, [.present(letter: "F", percentage: Decimal.zero), .missing(.dash), .missing(.blank)])
    }

    // MARK: - 6. Reporting dates

    func testReportingDates_CrossYearBoundaryFromBaselineStructure() throws {
        let html = try SchoologyFixtures.baselineVariant(
            replacing: #"<span class="s-parent-digest-date-start">03/02/26</span> - <span class="s-parent-digest-date-end">03/09/26</span>"#,
            with: #"<span class="s-parent-digest-date-start">12/29/25</span> - <span class="s-parent-digest-date-end">01/05/26</span>"#)
        let result = try parseSchoologyWeeklyEmail(html: html)
        XCTAssertEqual(result.reportingPeriod, ReportingPeriod(start: date(2025, 12, 29), end: date(2026, 1, 5)))
        XCTAssertEqual(result.students.map(\.courses.count), [13, 12])
    }

    func testReportingDates_SameDayRangeIsValid() throws {
        let html = SyntheticDigest.document(start: "03/09/26", end: "03/09/26", students: [
            SyntheticDigest.student("Student Gamma", rows: [SyntheticDigest.course("Example Course 81: Section 1", gradeHTML: "A")]),
        ])
        XCTAssertEqual(try parseSchoologyWeeklyEmail(html: html).reportingPeriod,
                       ReportingPeriod(start: date(2026, 3, 9), end: date(2026, 3, 9)))
    }

    // MARK: - 7. Reporting context

    func testContext_AbsentGradingPeriodStaysAbsentAndNoYearIsInferred() throws {
        let html = SyntheticDigest.document(students: [
            SyntheticDigest.student("Student Gamma", rows: [
                SyntheticDigest.course("Example Course 91: Section 1", gradingPeriodHTML: nil, gradeHTML: SyntheticDigest.overall("A", "95%")),
                SyntheticDigest.course("Example Course 92: Section 1", gradingPeriodHTML: "Synthetic Term B (01 Feb - 30 Apr)", gradeHTML: "B"),
            ]),
        ])
        let courses = try parseSchoologyWeeklyEmail(html: html).students.first?.courses
        XCTAssertEqual(courses?.map(\.gradingPeriodText), [nil, "Synthetic Term B (01 Feb - 30 Apr)"])
    }

    // MARK: - 8. HTML variations

    func testHTML_OrdinaryWhitespaceCollapsedInLabelsAndGrades() throws {
        let html = SyntheticDigest.document(students: [
            SyntheticDigest.student("\n  Student \t Gamma\n", rows: [
                SyntheticDigest.course(
                    "\n   Example\tCourse   21:\n  Section 2  ",
                    gradingPeriodHTML: "\n  Synthetic   Term\tC  ",
                    gradeHTML: "\n  A-\n  <span class=\"numeric-grade-value\">\n<span class=\"rounded-grade\"> 91.25% </span></span>\n"),
            ]),
        ])
        let result = try parseSchoologyWeeklyEmail(html: html)
        XCTAssertEqual(result.students, [ExtractedStudent(studentLabel: "Student Gamma", courses: [
            ExtractedCourse(courseLabel: "Example Course 21: Section 2", gradingPeriodText: "Synthetic Term C",
                            overallGrade: .present(letter: "A-", percentage: pct("91.25"))),
        ])])
    }

    func testHTML_NestedFormattingPreservesMeaningfulText() throws {
        let html = SyntheticDigest.document(students: [
            SyntheticDigest.student("<span>Student</span> <strong>Gamma</strong>", rows: [
                SyntheticDigest.course(
                    "<strong>Example</strong> <em>Course</em> 22: <span><b>Section</b> 3</span>",
                    gradeHTML: "<strong>A-</strong> " + #"<span class="numeric-grade-value"><span class="rounded-grade" title="Synthetic label">91.25%</span></span>"#),
                SyntheticDigest.course("Example Course 23: Section 1", gradeHTML: "<b><i>B+</i></b>"),
            ]),
        ])
        let result = try parseSchoologyWeeklyEmail(html: html)
        XCTAssertEqual(result.students.map(\.studentLabel), ["Student Gamma"])
        XCTAssertEqual(result.students.first?.courses.map(\.courseLabel), ["Example Course 22: Section 3", "Example Course 23: Section 1"])
        XCTAssertEqual(result.students.first?.courses.map(\.overallGrade), [
            .present(letter: "A-", percentage: pct("91.25")),
            .present(letter: "B+", percentage: nil),
        ])
    }

    func testHTML_CharacterEntitiesDecodedAndNoBreakSpacePreserved() throws {
        let html = SyntheticDigest.document(students: [
            SyntheticDigest.student("Student O&#39;Gamma", rows: [
                SyntheticDigest.course("Art &amp; Design: Section 1", gradeHTML: "A"),
                SyntheticDigest.course("Caf&#233; Studies &#x2014; &lt;Lab&gt;", gradeHTML: "B"),
                SyntheticDigest.course("Example&nbsp;Course 24", gradingPeriodHTML: "T2&nbsp;(Synthetic)", gradeHTML: "C"),
            ]),
        ])
        let result = try parseSchoologyWeeklyEmail(html: html)
        XCTAssertEqual(result.students.map(\.studentLabel), ["Student O'Gamma"])
        XCTAssertEqual(result.students.first?.courses.map(\.courseLabel),
                       ["Art & Design: Section 1", "Café Studies \u{2014} <Lab>", "Example\u{00A0}Course 24"])
        XCTAssertEqual(result.students.first?.courses.last?.gradingPeriodText, "T2\u{00A0}(Synthetic)")
    }

    // MARK: - 9. Errors

    func testErrors_MissingReportingDates() throws {
        let noRange = try SchoologyFixtures.baselineVariant(
            replacing: #"<span class="s-parent-digest-date-start">03/02/26</span> - <span class="s-parent-digest-date-end">03/09/26</span>"#,
            with: "")
        assertExtractionError(.missingReportingDates, try parseSchoologyWeeklyEmail(html: noRange))

        let noStart = try SchoologyFixtures.baselineVariant(
            replacing: #"<span class="s-parent-digest-date-start">03/02/26</span> - "#, with: "")
        assertExtractionError(.missingReportingDates, try parseSchoologyWeeklyEmail(html: noStart))

        let noEnd = SyntheticDigest.document(end: nil, students: [
            SyntheticDigest.student("Student Gamma", rows: [SyntheticDigest.course("Example Course 01: Section 1", gradeHTML: "A")]),
        ])
        assertExtractionError(.missingReportingDates, try parseSchoologyWeeklyEmail(html: noEnd))
    }

    func testErrors_InvalidReportingDates() throws {
        for bad in ["02/30/26", "13/01/26", "02/29/25", "Synthetic"] {
            let html = SyntheticDigest.document(start: bad, end: "03/09/26", students: [
                SyntheticDigest.student("Student Gamma", rows: [SyntheticDigest.course("Example Course 01: Section 1", gradeHTML: "A")]),
            ])
            assertExtractionError(.invalidReportingDate(text: bad), try parseSchoologyWeeklyEmail(html: html))
        }
    }

    func testErrors_ReversedReportingRange() throws {
        let html = try SchoologyFixtures.baselineVariant(
            replacing: #"<span class="s-parent-digest-date-start">03/02/26</span> - <span class="s-parent-digest-date-end">03/09/26</span>"#,
            with: #"<span class="s-parent-digest-date-start">03/09/26</span> - <span class="s-parent-digest-date-end">03/02/26</span>"#)
        assertExtractionError(.reversedReportingRange, try parseSchoologyWeeklyEmail(html: html))
    }

    func testErrors_MalformedNumericGradeInBaselineIsNotDropped() throws {
        let html = try SchoologyFixtures.baselineVariant(replacing: "73.63%</span>", with: "7x.63%</span>")
        assertExtractionError(.malformedGrade(studentLabel: "Student Beta", courseLabel: "Example Course 03: Section 1"),
                              try parseSchoologyWeeklyEmail(html: html))
    }

    func testErrors_MalformedNumericGradeVariants() throws {
        for bad in ["73.1.7%", "%", "abc%", "NaN%"] {
            let html = SyntheticDigest.document(students: [
                SyntheticDigest.student("Student Gamma", rows: [SyntheticDigest.course("Example Course 01: Section 1", gradeHTML: "A")]),
                SyntheticDigest.student("Student Delta", rows: [SyntheticDigest.course("Example Course 02: Section 1", gradeHTML: SyntheticDigest.overall("B", bad))]),
            ])
            assertExtractionError(.malformedGrade(studentLabel: "Student Delta", courseLabel: "Example Course 02: Section 1"),
                                  try parseSchoologyWeeklyEmail(html: html))
        }
    }

    func testErrors_UnsupportedStructureWithoutStudentSections() throws {
        assertExtractionError(.unsupportedReportStructure, try parseSchoologyWeeklyEmail(html: SyntheticDigest.document(students: [])))
    }

    func testErrors_UnsupportedStructureWhenStudentHasNoCourseTable() throws {
        let html = SyntheticDigest.document(students: [
            SyntheticDigest.student("Student Gamma", rows: [SyntheticDigest.course("Example Course 01: Section 1", gradeHTML: "A")]),
            SyntheticDigest.student("Student Delta", rows: [], includeSummaryTable: false),
        ])
        assertExtractionError(.unsupportedReportStructure, try parseSchoologyWeeklyEmail(html: html))
    }

    func testErrors_UnsupportedStructureWhenCourseRowLacksGradeCell() throws {
        let html = SyntheticDigest.document(students: [
            SyntheticDigest.student("Student Gamma", rows: [SyntheticDigest.course("Example Course 01: Section 1", gradeHTML: "A")]),
            SyntheticDigest.student("Student Delta", rows: [
                SyntheticDigest.course("Example Course 02: Section 1", gradeHTML: "B"),
                SyntheticDigest.courseWithoutGradeCell("Example Course 03: Section 1"),
            ]),
        ])
        assertExtractionError(.unsupportedReportStructure, try parseSchoologyWeeklyEmail(html: html))
    }

    func testErrors_UnsupportedStructureForBlankStudentOrCourseLabel() throws {
        let blankStudent = SyntheticDigest.document(students: [
            SyntheticDigest.student(" \n ", rows: [SyntheticDigest.course("Example Course 01: Section 1", gradeHTML: "A")]),
        ])
        assertExtractionError(.unsupportedReportStructure, try parseSchoologyWeeklyEmail(html: blankStudent))

        let blankCourse = SyntheticDigest.document(students: [
            SyntheticDigest.student("Student Gamma", rows: [
                SyntheticDigest.course("Example Course 01: Section 1", gradeHTML: "A"),
                SyntheticDigest.course("<span> </span>", gradeHTML: "B"),
            ]),
        ])
        assertExtractionError(.unsupportedReportStructure, try parseSchoologyWeeklyEmail(html: blankCourse))
    }

    // MARK: - 10. Complete course extraction

    func testCompleteExtraction_RetainsNonacademicLabelsAndMissingRows() throws {
        let rows: [(String, String, ExtractedOverallGrade)] = [
            ("Homeroom Advisory", SyntheticDigest.dash, .missing(.dash)),
            ("Lunch: Grade 7", "", .missing(.blank)),
            ("Example Club: Robotics", "P", .present(letter: "P", percentage: nil)),
            ("Study Hall", SyntheticDigest.overall("A", "100%"), .present(letter: "A", percentage: pct("100"))),
        ]
        let html = SyntheticDigest.document(students: [
            SyntheticDigest.student("Student Gamma", rows: rows.map { SyntheticDigest.course($0.0, gradeHTML: $0.1) }),
        ])
        let courses = try parseSchoologyWeeklyEmail(html: html).students.first?.courses
        XCTAssertEqual(courses, rows.map { ExtractedCourse(courseLabel: $0.0, gradingPeriodText: gp, overallGrade: $0.2) })
    }
}

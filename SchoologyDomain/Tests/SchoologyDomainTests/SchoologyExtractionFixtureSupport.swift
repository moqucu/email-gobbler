import Foundation
@testable import SchoologyDomain

struct FixtureSetupError: Error, CustomStringConvertible {
    let description: String
}

enum SchoologyFixtures {
    static let noBreakSpace = "\u{00A0}"
    static let baselineGradingPeriod = "25-26 T2\u{00A0}(14 Jan - 12 Jun)"

    static func data(_ name: String, _ ext: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
            throw FixtureSetupError(description: "Missing test resource Fixtures/\(name).\(ext)")
        }
        return try Data(contentsOf: url)
    }

    static func baselineHTML() throws -> String {
        let data = try data("schoology-weekly.synthetic", "html")
        guard let html = String(data: data, encoding: .utf8) else {
            throw FixtureSetupError(description: "Baseline HTML is not UTF-8")
        }
        return html
    }

    /// Derives a variant from the baseline; fails setup (not the parser) if the anchor text drifts.
    static func baselineVariant(replacing target: String, with replacement: String, occurrences: Int = 1) throws -> String {
        let html = try baselineHTML()
        let found = html.components(separatedBy: target).count - 1
        guard found == occurrences else {
            throw FixtureSetupError(description: "Expected \(occurrences) occurrence(s) of \(target.debugDescription), found \(found)")
        }
        return html.replacingOccurrences(of: target, with: replacement)
    }

    static func oracle() throws -> Oracle {
        try JSONDecoder().decode(Oracle.self, from: data("schoology-weekly.expected", "json"))
    }
}

/// Test-only view of schoology-weekly.expected.json. Not a production API.
struct Oracle: Decodable {
    struct Period: Decodable { let start: String; let end: String }
    struct Student: Decodable { let studentLabel: String; let courses: [Course] }
    struct Course: Decodable { let courseLabel: String; let gradingPeriodText: String?; let grade: Grade }
    struct Grade: Decodable { let state: String; let marker: String?; let letter: String?; let percentage: String? }

    let fixture: String
    let reportingPeriod: Period
    let students: [Student]

    func asExtraction() throws -> SchoologyWeeklyExtraction {
        SchoologyWeeklyExtraction(
            reportingPeriod: ReportingPeriod(start: try Self.isoDate(reportingPeriod.start), end: try Self.isoDate(reportingPeriod.end)),
            students: try students.map { student in
                ExtractedStudent(studentLabel: student.studentLabel, courses: try student.courses.map { course in
                    ExtractedCourse(courseLabel: course.courseLabel, gradingPeriodText: course.gradingPeriodText, overallGrade: try Self.grade(course.grade))
                })
            }
        )
    }

    private static func isoDate(_ text: String) throws -> CalendarDate {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { throw FixtureSetupError(description: "Bad oracle date \(text)") }
        return try CalendarDate(year: parts[0], month: parts[1], day: parts[2])
    }

    private static func grade(_ grade: Grade) throws -> ExtractedOverallGrade {
        switch (grade.state, grade.marker, grade.letter, grade.percentage) {
        case ("missing", "-", nil, nil):
            return .missing(.dash)
        case ("present", nil, let letter?, nil):
            return .present(letter: letter, percentage: nil)
        case ("present", nil, let letter?, let text?):
            guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
                throw FixtureSetupError(description: "Bad oracle percentage \(text)")
            }
            return .present(letter: letter, percentage: value)
        default:
            throw FixtureSetupError(description: "Unrecognized oracle grade \(grade)")
        }
    }
}

/// Builds CONSTRUCTED edge-case digests for SG-02 tests. These mirror the class names and
/// row layout of the anonymized baseline, but are not additional observed Schoology formats.
enum SyntheticDigest {
    static let dash = #"<span class="empty">-</span>"#

    static func overall(_ letter: String, _ percentText: String) -> String {
        #"\#(letter) <span class="numeric-grade-value"><span class="rounded-grade" title="Synthetic label">\#(percentText)</span></span>"# + "\n"
    }

    static func assignment(_ titleHTML: String, gradeHTML: String) -> String {
        """
         <tr class="s-parent-digest-grade-row odd">
        <td class="s-parent-digest-cell s-parent-digest-title-cell"><div class="s-parent-digest-grade-title">
        <div class="mini inline-icon grade-item-icon"></div>
        <a href="https://example.invalid/resource/assignment">\(titleHTML)</a>
        </div></td>
        <td class="s-parent-digest-cell s-parent-digest-grade-cell"><div class="course-summary-grade">\(gradeHTML)</div></td> </tr>

        """
    }

    static func course(
        _ labelHTML: String,
        gradingPeriodHTML: String? = SchoologyFixtures.baselineGradingPeriod,
        gradeHTML: String,
        attendanceHTML: String = dash,
        assignments: [String] = []
    ) -> String {
        let period = gradingPeriodHTML.map { #"<div class="s-parent-digest-grading-period-title">\#($0)</div>"# } ?? ""
        return """
         <tr class="s-parent-digest-course-row odd">
        <td class="s-parent-digest-cell s-parent-digest-title-cell">
        <a href="https://example.invalid/resource/course">\(labelHTML)</a>\(period)
        </td>
        <td class="s-parent-digest-cell s-parent-digest-grade-cell">\(gradeHTML)</td>
        <td class="s-parent-digest-cell s-parent-digest-attendance-cell">
        <table><tbody>
         <tr class="odd"><td>\(attendanceHTML)</td> </tr>
        </tbody></table>
        </td> </tr>

        """ + assignments.joined()
    }

    static func courseWithoutGradeCell(_ labelHTML: String) -> String {
        """
         <tr class="s-parent-digest-course-row odd">
        <td class="s-parent-digest-cell s-parent-digest-title-cell">
        <a href="https://example.invalid/resource/course">\(labelHTML)</a><div class="s-parent-digest-grading-period-title">\(SchoologyFixtures.baselineGradingPeriod)</div>
        </td>
        </tr>

        """
    }

    static func recentActivity(_ studentLabelHTML: String, gradeHTML: String) -> String {
        """
        <div class="s-parent-digest-recent-activity">
        <table><tbody><tr class="odd"><td class="s-parent-feed-cell">
        <span class="edge-sentence"><a href="https://example.invalid/resource/activity">\(studentLabelHTML)</a> received <span class="grade-post-grade">\(gradeHTML)</span> for <a href="https://example.invalid/resource/assignment">Example Assignment 99</a></span>
        </td></tr></tbody></table>
        </div>

        """
    }

    static func student(_ labelHTML: String, rows: [String], includeSummaryTable: Bool = true, trailing: String = "") -> String {
        let header = """
        <div class="s-parent-digest-username">
        <table><tbody>
         <tr class="odd">
        <td class="s-parent-digest-user-picture-cell"><div class="picture"></div></td>
        <td class="s-parent-digest-username-cell"><a href="https://example.invalid/resource/student">\(labelHTML)</a></td> </tr>
        </tbody></table>
        </div>

        """
        guard includeSummaryTable else { return header + trailing }
        return header + """
        <div class="s-parent-digest-summary">
        <table class="s-parent-digest-table">
         <thead><tr>
        <th class="s-parent-digest-cell s-parent-digest-title-cell s-parent-digest-header-cell">Course Summary</th>
        <th class="s-parent-digest-cell s-parent-digest-grade-cell s-parent-digest-header-cell">Grade<div class="s-parent-digest-grade-column-sub-title">(current grading period)</div></th>
        <th class="s-parent-digest-cell s-parent-digest-attendance-cell s-parent-digest-header-cell">Attendance</th> </tr></thead>
        <tbody>
        \(rows.joined())
         <tr class="odd"><td colspan="3" class="s-parent-digest-empty-cell"> </td> </tr>
        </tbody>
        </table>
        </div>

        """ + trailing
    }

    static func document(start: String? = "03/02/26", end: String? = "03/09/26", students: [String]) -> String {
        let startSpan = start.map { #"<span class="s-parent-digest-date-start">\#($0)</span>"# } ?? ""
        let endSpan = end.map { #"<span class="s-parent-digest-date-end">\#($0)</span>"# } ?? ""
        return """
        <html><head></head><body>
        <div class="s-parent-digest-wrapper">
        <div class="s-parent-digest-banner"><table><tbody><tr class="odd"><td>
        <div class="s-parent-digest-date-range">
        \(startSpan) - \(endSpan)
        </div>
        </td></tr></tbody></table></div>
        \(students.joined())
        </div>
        </body></html>
        """
    }
}

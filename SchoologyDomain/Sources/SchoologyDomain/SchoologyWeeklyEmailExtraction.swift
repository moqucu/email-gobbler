import Foundation
import SwiftSoup

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

func parseDate(_ text: String) throws -> CalendarDate? {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return nil }
    let parts = t.split(separator: "/")
    guard parts.count == 3,
          let m = Int(parts[0]),
          let d = Int(parts[1]),
          let yStr = Int(parts[2]) else {
        throw SchoologyExtractionError.invalidReportingDate(text: t)
    }
    let y = 2000 + yStr
    do {
        return try CalendarDate(year: y, month: m, day: d)
    } catch {
        throw SchoologyExtractionError.invalidReportingDate(text: t)
    }
}

public func parseSchoologyWeeklyEmail(html: String) throws -> SchoologyWeeklyExtraction {
    let nbspHolder = "\u{E000}"
    var processedHtml = html.replacingOccurrences(of: "\u{00A0}", with: nbspHolder)
    processedHtml = processedHtml.replacingOccurrences(of: "&nbsp;", with: nbspHolder)
    processedHtml = processedHtml.replacingOccurrences(of: "&#160;", with: nbspHolder)
    
    let doc: Document
    do {
        doc = try SwiftSoup.parse(processedHtml)
    } catch {
        throw SchoologyExtractionError.unsupportedReportStructure
    }

    func getText(_ el: Element?) throws -> String {
        guard let el = el else { return "" }
        let t = try el.text(trimAndNormaliseWhitespace: true)
        return t.replacingOccurrences(of: nbspHolder, with: "\u{00A0}")
    }

    // Reporting Period
    let startEl = try doc.select(".s-parent-digest-date-start").first()
    let endEl = try doc.select(".s-parent-digest-date-end").first()
    
    let startText = try getText(startEl)
    let endText = try getText(endEl)
    
    if startText.isEmpty || endText.isEmpty {
        throw SchoologyExtractionError.missingReportingDates
    }

    guard let start = try parseDate(startText), let end = try parseDate(endText) else {
        throw SchoologyExtractionError.missingReportingDates
    }
    
    if end < start {
        throw SchoologyExtractionError.reversedReportingRange
    }
    
    let period = ReportingPeriod(start: start, end: end)

    var students: [ExtractedStudent] = []
    
    // Students and courses
    let wrappers = try doc.select(".s-parent-digest-username, .s-parent-digest-summary")
    
    var currentStudentLabel: String?
    
    for wrapper in wrappers {
        if wrapper.hasClass("s-parent-digest-username") {
            if currentStudentLabel != nil {
                throw SchoologyExtractionError.unsupportedReportStructure
            }
            if let a = try wrapper.select(".s-parent-digest-username-cell a").first() {
                let text = try getText(a)
                if text.isEmpty {
                    throw SchoologyExtractionError.unsupportedReportStructure
                }
                currentStudentLabel = text
            } else {
                throw SchoologyExtractionError.unsupportedReportStructure
            }
        } else if wrapper.hasClass("s-parent-digest-summary") {
            guard let studentLabel = currentStudentLabel else {
                throw SchoologyExtractionError.unsupportedReportStructure
            }
            let rows = try wrapper.select("tr.s-parent-digest-course-row")
            if rows.isEmpty() {
                throw SchoologyExtractionError.unsupportedReportStructure
            }
            var courses: [ExtractedCourse] = []
            for row in rows {
                guard let titleA = try row.select(".s-parent-digest-title-cell a").first() else {
                    throw SchoologyExtractionError.unsupportedReportStructure
                }
                let courseLabel = try getText(titleA)
                if courseLabel.isEmpty {
                    throw SchoologyExtractionError.unsupportedReportStructure
                }
                
                let gradingPeriodEl = try row.select(".s-parent-digest-grading-period-title").first()
                var gradingPeriodText: String? = nil
                if let gpEl = gradingPeriodEl {
                    gradingPeriodText = try getText(gpEl)
                }
                
                guard let gradeCell = try row.select(".s-parent-digest-grade-cell").first() else {
                    throw SchoologyExtractionError.unsupportedReportStructure
                }
                
                let gradeText = try getText(gradeCell)
                
                let overallGrade: ExtractedOverallGrade
                if gradeText.isEmpty {
                    overallGrade = .missing(.blank)
                } else if gradeText == "-" {
                    overallGrade = .missing(.dash)
                } else {
                    var letter = ""
                    var percentageText: String? = nil
                    
                    if let roundedGrade = try gradeCell.select(".rounded-grade").first() {
                        percentageText = try getText(roundedGrade)
                        // Remove numeric-grade-value from DOM to leave just the letter
                        try gradeCell.select(".numeric-grade-value").remove()
                        letter = try getText(gradeCell)
                    } else {
                        letter = try getText(gradeCell)
                    }
                    
                    if letter.isEmpty || letter == "-" {
                        throw SchoologyExtractionError.malformedGrade(studentLabel: studentLabel, courseLabel: courseLabel)
                    }
                    
                    var percentage: Decimal? = nil
                    if let pText = percentageText {
                        if pText.hasSuffix("%") {
                            let numStr = String(pText.dropLast())
                            // Strict validation for decimals
                            if numStr.range(of: "^-?[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil {
                                if let dec = Decimal(string: numStr, locale: Locale(identifier: "en_US_POSIX")), !dec.isNaN {
                                    percentage = dec
                                } else {
                                    throw SchoologyExtractionError.malformedGrade(studentLabel: studentLabel, courseLabel: courseLabel)
                                }
                            } else {
                                throw SchoologyExtractionError.malformedGrade(studentLabel: studentLabel, courseLabel: courseLabel)
                            }
                        } else {
                            throw SchoologyExtractionError.malformedGrade(studentLabel: studentLabel, courseLabel: courseLabel)
                        }
                    }
                    overallGrade = .present(letter: letter, percentage: percentage)
                }
                courses.append(ExtractedCourse(courseLabel: courseLabel, gradingPeriodText: gradingPeriodText, overallGrade: overallGrade))
            }
            students.append(ExtractedStudent(studentLabel: studentLabel, courses: courses))
            currentStudentLabel = nil
        }
    }
    
    if currentStudentLabel != nil {
        throw SchoologyExtractionError.unsupportedReportStructure
    }
    
    if students.isEmpty {
        throw SchoologyExtractionError.unsupportedReportStructure
    }
    
    return SchoologyWeeklyExtraction(reportingPeriod: period, students: students)
}

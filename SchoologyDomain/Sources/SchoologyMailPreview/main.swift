import Foundation
import SchoologyDomain

enum PreviewError: Error, CustomStringConvertible {
    case usage
    case mailAccess(String)

    var description: String {
        switch self {
        case .usage:
            return "Usage: schoology-mail-preview --eml <path> | --mail-subject <subject text>"
        case .mailAccess(let message):
            return "Mail access failed: \(message)"
        }
    }
}

func appleScriptString(_ text: String) -> String {
    "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

func messageFromMail(subject: String) throws -> Data {
    guard !subject.isEmpty, !subject.contains("\n"), !subject.contains("\r") else {
        throw PreviewError.usage
    }
    let script = """
    tell application "Mail"
        set matches to messages of inbox whose subject contains \(appleScriptString(subject))
        if (count of matches) is 0 then error "No matching message in Inbox"
        set chosen to item 1 of matches
        repeat with candidate in matches
            if (date received of candidate) > (date received of chosen) then set chosen to candidate
        end repeat
        return source of chosen
    end tell
    """
    guard let appleScript = NSAppleScript(source: script) else {
        throw PreviewError.mailAccess("Unable to create AppleScript")
    }
    var errorInfo: NSDictionary?
    let result = appleScript.executeAndReturnError(&errorInfo)
    if let errorInfo {
        throw PreviewError.mailAccess("\(errorInfo)")
    }
    guard let source = result.stringValue else {
        throw PreviewError.mailAccess("Mail returned no message source")
    }
    return Data(source.utf8)
}

func preview() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 2 else { throw PreviewError.usage }
    let message: Data
    switch arguments[0] {
    case "--eml":
        message = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
    case "--mail-subject":
        message = try messageFromMail(subject: arguments[1])
    default:
        throw PreviewError.usage
    }

    let html = try MailDecoder.html(from: message)
    let extraction = try parseSchoologyWeeklyEmail(html: html)
    print("Reporting period: \(extraction.reportingPeriod.start) to \(extraction.reportingPeriod.end)")
    print("Students: \(extraction.students.count)")
    for student in extraction.students {
        let graded = student.courses.filter {
            if case .present = $0.overallGrade { return true }
            return false
        }.count
        print("\(student.studentLabel): \(student.courses.count) courses, \(graded) graded")
    }
}

do {
    try preview()
} catch {
    fputs("schoology-mail-preview: \(error)\n", stderr)
    exit(1)
}

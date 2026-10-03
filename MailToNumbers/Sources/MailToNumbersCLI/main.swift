import Foundation
import MailNumbersCore
import SchoologyGrades

enum PreviewError: Error, CustomStringConvertible {
    case usage
    case mailAccess(String)

    var description: String {
        switch self {
        case .usage:
            return "Usage: mail-to-numbers (--eml <path> | --mail-subject <text>) [--numbers <path> --sheet <name> --student <exact label> [--apply --backup <path> [--consume]]]"
        case .mailAccess(let message):
            return "Mail access failed: \(message)"
        }
    }
}


func messageFromMail(subject: String) throws -> FetchedMailMessage {
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
        set a to account of mailbox of chosen
        return {source of chosen, id of chosen, id of a, message id of chosen}
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
    guard result.numberOfItems == 4,
          let source = result.atIndex(1)?.stringValue,
          let accountID = result.atIndex(3)?.stringValue,
          let rfcMessageID = result.atIndex(4)?.stringValue,
          let idDescriptor = result.atIndex(2),
          idDescriptor.int32Value > 0 else {
        throw PreviewError.mailAccess("Mail returned incomplete message identity")
    }
    return FetchedMailMessage(source: Data(source.utf8), id: idDescriptor.int32Value,
                              accountID: accountID, rfcMessageID: rfcMessageID)
}

func preview() throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    let apply = arguments.contains("--apply")
    let shouldConsume = arguments.contains("--consume")
    arguments.removeAll { $0 == "--apply" || $0 == "--consume" }
    guard arguments.count.isMultiple(of: 2) else { throw PreviewError.usage }
    var options: [String: String] = [:]
    for index in stride(from: 0, to: arguments.count, by: 2) {
        let key = arguments[index]
        guard ["--eml", "--mail-subject", "--numbers", "--sheet", "--student", "--backup"].contains(key),
              options[key] == nil else { throw PreviewError.usage }
        options[key] = arguments[index + 1]
    }
    guard (options["--eml"] == nil) != (options["--mail-subject"] == nil) else {
        throw PreviewError.usage
    }
    let workbookOptions = [options["--numbers"], options["--sheet"], options["--student"]]
    guard workbookOptions.allSatisfy({ $0 == nil }) || workbookOptions.allSatisfy({ $0 != nil }) else {
        throw PreviewError.usage
    }
    guard (apply && options["--backup"] != nil && options["--numbers"] != nil)
        || (!apply && options["--backup"] == nil) else { throw PreviewError.usage }
    guard !shouldConsume || (apply && options["--mail-subject"] != nil) else {
        throw PreviewError.usage
    }
    let message: Data
    var fetchedMail: FetchedMailMessage?
    if let path = options["--eml"] {
        message = try Data(contentsOf: URL(fileURLWithPath: path))
    } else {
        fetchedMail = try messageFromMail(subject: options["--mail-subject"]!)
        message = fetchedMail!.source
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

    if let workbookPath = options["--numbers"], let sheetName = options["--sheet"],
       let studentLabel = options["--student"] {
        let snapshot = try readNumbersSnapshot(at: URL(fileURLWithPath: workbookPath), sheetName: sheetName)
        let plan = try planWorkbookUpdate(report: extraction, studentLabel: studentLabel, sheet: snapshot)
        switch plan.action {
        case .insert(let row): print("DRY RUN: insert row \(row) in \(sheetName)")
        case .replace(let row): print("DRY RUN: replace row \(row) in \(sheetName)")
        }
        print("Date: \(String(format: "%04d-%02d-%02d", plan.weekEnd.year, plan.weekEnd.month, plan.weekEnd.day))")
        for cell in plan.cells {
            let header = snapshot.headers[cell.column - 1]
            let label = header.isEmpty ? "letter" : header
            print("Column \(cell.column) (\(label)): \(cell.value ?? "<blank>")")
        }
        print("Ignored courses without grades: \(plan.ignoredMissingCourses.count)")
        if apply, let backupPath = options["--backup"] {
            print("Backup target: \(backupPath)")
            let write = {
                try writeNumbersUpdate(at: URL(fileURLWithPath: workbookPath), sheetName: sheetName,
                                       snapshot: snapshot, plan: plan,
                                       backupURL: URL(fileURLWithPath: backupPath))
                print("Workbook saved and verified")
            }
            if shouldConsume, let fetchedMail {
                try writeThenConsume(write: write, consume: {
                    try consumeMailMessage(fetchedMail)
                    print("Mail message marked read and moved to iCloud Archive")
                })
            } else {
                try write()
            }
        }
    }
}

do {
    try preview()
} catch {
    fputs("mail-to-numbers: \(error)\n", stderr)
    exit(1)
}

import EtradeDividends
import Foundation
import EmailGobblerCore
import SchoologyGrades

let usage = """
Usage:
  email-gobbler schoology-grades (--eml <path> | --mail [--subject <text>])
      [--numbers <path> --sheet <name> --student <label> [--apply --backup-dir <dir> [--consume]]]
  email-gobbler etrade-dividends (--eml <path> | --mail [--subject <text>])
      [--numbers <path> [--sheet <name>] [--apply --backup-dir <dir> [--consume]]]
"""

struct UsageError: Error, CustomStringConvertible {
    var description: String { usage }
}

struct Options {
    let useCase: any EmailUseCase
    let emlPath: String?
    let workbook: URL?
    let backupDirectory: URL?
    let apply: Bool
    let consume: Bool

    init(arguments: [String]) throws {
        guard let command = arguments.first else { throw UsageError() }
        var rest = Array(arguments.dropFirst())
        let flags = ["--mail", "--apply", "--consume"]
        let mail = rest.contains("--mail")
        apply = rest.contains("--apply")
        consume = rest.contains("--consume")
        rest.removeAll { flags.contains($0) }
        guard rest.count.isMultiple(of: 2) else { throw UsageError() }
        var values: [String: String] = [:]
        for index in stride(from: 0, to: rest.count, by: 2) {
            let key = rest[index]
            guard ["--eml", "--subject", "--numbers", "--sheet", "--student", "--backup-dir"].contains(key),
                  values[key] == nil else { throw UsageError() }
            values[key] = rest[index + 1]
        }
        emlPath = values["--eml"]
        guard (emlPath != nil) != mail, values["--subject"] == nil || mail else { throw UsageError() }
        workbook = values["--numbers"].map { URL(fileURLWithPath: $0) }
        backupDirectory = values["--backup-dir"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        guard apply == (backupDirectory != nil), !apply || workbook != nil, !consume || (apply && mail) else {
            throw UsageError()
        }

        switch command {
        case "schoology-grades":
            let query = values["--subject"].map { MailQuery(subjectContains: $0, senderContains: nil) }
                ?? SchoologyGradesUseCase.defaultQuery
            guard workbook == nil || (values["--sheet"] != nil && values["--student"] != nil) else { throw UsageError() }
            let routes = workbook.map { workbook in
                [StudentRoute(studentLabel: values["--student"]!, target: SheetTarget(workbook: workbook, sheetName: values["--sheet"]!))]
            } ?? []
            useCase = SchoologyGradesUseCase(routes: routes, mailQuery: query)
        case "etrade-dividends":
            guard values["--student"] == nil else { throw UsageError() }
            let defaults = EtradeDividendsUseCase.defaultQuery
            let query = values["--subject"].map { MailQuery(subjectContains: $0, senderContains: defaults.senderContains) }
                ?? defaults
            let sheetName = values["--sheet"] ?? EtradeDividendsUseCase.defaultSheetName
            useCase = EtradeDividendsUseCase(target: workbook.map { SheetTarget(workbook: $0, sheetName: sheetName) },
                                             mailQuery: query)
        default:
            throw UsageError()
        }
    }
}

func run() throws {
    let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
    var backupSequence = 0

    func process(source: Data, fetched: FetchedMailMessage?) throws {
        let html = try MailDecoder.html(from: source)
        var actions = MessageActions()
        if options.workbook != nil {
            actions.readSheet = { target in try readSheetSnapshot(workbook: target.workbook, sheetName: target.sheetName) }
            if options.apply, let directory = options.backupDirectory {
                actions.write = { plan, sheet in
                    backupSequence += 1
                    let backup = backupURL(directory: directory, workbook: plan.target.workbook,
                                           timestamp: Date(), sequence: backupSequence)
                    try writeSheetUpdate(workbook: plan.target.workbook, sheetName: plan.target.sheetName,
                                         plan: plan.update, plannedFrom: sheet, backup: backup)
                    print("\(plan.target): saved and verified; backup at \(backup.path)")
                }
            }
        }
        if options.consume, let fetched {
            actions.consume = { try consumeMailMessage(fetched) }
        }
        let report = try processMessage(html: html, useCase: options.useCase, actions: actions)
        report.summary.forEach { print($0) }
        report.notes.forEach { print($0) }
        for target in report.targets {
            print("\(target.target):")
            target.preview.forEach { print("  " + $0) }
        }
        if report.consumed { print("Mail message marked read and moved to iCloud Archive") }
    }

    if let path = options.emlPath {
        try process(source: Data(contentsOf: URL(fileURLWithPath: path)), fetched: nil)
        return
    }
    let messages = try listInboxMessages(options.useCase.mailQuery)
    print("Matching Inbox messages: \(messages.count)")
    try processInOrder(Array(messages.enumerated())) { index, ref in
        print("--- Message \(index + 1) of \(messages.count)")
        let fetched = try fetchMailMessage(ref)
        try process(source: fetched.source, fetched: fetched)
    }
}

do {
    try run()
} catch {
    fputs("email-gobbler: \(error)\n", stderr)
    exit(1)
}

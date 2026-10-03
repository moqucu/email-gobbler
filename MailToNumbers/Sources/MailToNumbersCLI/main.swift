import EtradeDividends
import Foundation
import MailNumbersCore
import SchoologyGrades

let usage = """
Usage:
  mail-to-numbers schoology-grades (--eml <path> | --mail [--subject <text>])
      [--numbers <path> --sheet <name> --student <label> [--apply --backup-dir <dir> [--consume]]]
  mail-to-numbers etrade-dividends (--eml <path> | --mail [--subject <text>])
      [--numbers <path> [--sheet <name>] [--apply --backup-dir <dir> [--consume]]]
"""

struct UsageError: Error, CustomStringConvertible {
    var description: String { usage }
}

struct Options {
    let useCase: any MailToNumbersUseCase
    let emlPath: String?
    let workbook: URL?
    let sheetName: String?
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
            useCase = SchoologyGradesUseCase(studentLabel: values["--student"], mailQuery: query)
            sheetName = values["--sheet"]
        case "etrade-dividends":
            guard values["--student"] == nil else { throw UsageError() }
            let defaults = EtradeDividendsUseCase.defaultQuery
            let query = values["--subject"].map { MailQuery(subjectContains: $0, senderContains: defaults.senderContains) }
                ?? defaults
            useCase = EtradeDividendsUseCase(mailQuery: query)
            sheetName = values["--sheet"] ?? EtradeDividendsUseCase.defaultSheetName
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
        if let workbook = options.workbook, let sheetName = options.sheetName {
            actions.readSheet = { try readSheetSnapshot(workbook: workbook, sheetName: sheetName) }
            if options.apply, let directory = options.backupDirectory {
                actions.write = { plan, sheet in
                    backupSequence += 1
                    let backup = backupURL(directory: directory, workbook: workbook, timestamp: Date(), sequence: backupSequence)
                    try writeSheetUpdate(workbook: workbook, sheetName: sheetName, plan: plan, plannedFrom: sheet, backup: backup)
                    print("Workbook saved and verified; backup at \(backup.path)")
                }
            }
        }
        if options.consume, let fetched {
            actions.consume = {
                try consumeMailMessage(fetched)
                print("Mail message marked read and moved to iCloud Archive")
            }
        }
        _ = try processMessage(html: html, useCase: options.useCase, actions: actions) { print($0) }
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
    fputs("mail-to-numbers: \(error)\n", stderr)
    exit(1)
}

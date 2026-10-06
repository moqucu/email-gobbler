import Foundation

public struct MailQuery: Equatable, Sendable {
    public let subjectContains: String
    public let senderContains: String?

    public init(subjectContains: String, senderContains: String?) {
        self.subjectContains = subjectContains
        self.senderContains = senderContains
    }
}

/// A sheet in a workbook that a use case reads and may update.
public struct SheetTarget: Hashable, Sendable, CustomStringConvertible {
    public let workbook: URL
    public let sheetName: String

    public init(workbook: URL, sheetName: String) {
        self.workbook = workbook
        self.sheetName = sheetName
    }

    public var description: String { "\(workbook.lastPathComponent) › \(sheetName)" }
}

public struct TargetPlan: Equatable {
    public let target: SheetTarget
    public let update: SheetUpdatePlan

    public init(target: SheetTarget, update: SheetUpdatePlan) {
        self.target = target
        self.update = update
    }
}

public struct UseCasePlan: Equatable {
    public let targets: [TargetPlan]
    /// Human-readable notes such as ignored courses or already recorded payments.
    public let notes: [String]

    public init(targets: [TargetPlan], notes: [String]) {
        self.targets = targets
        self.notes = notes
    }
}

/// One kind of email that updates one or more Numbers sheets.
public protocol EmailUseCase {
    var mailQuery: MailQuery { get }
    /// Sheets read before planning. Without targets a run only summarizes.
    var targets: [SheetTarget] { get }
    func summarize(html: String) throws -> [String]
    func plan(html: String, sheets: [SheetTarget: SheetSnapshot]) throws -> UseCasePlan
}

public struct MessageActions {
    public var readSheet: ((SheetTarget) throws -> SheetSnapshot)?
    public var write: ((TargetPlan, SheetSnapshot) throws -> Void)?
    public var consume: (() throws -> Void)?

    public init(readSheet: ((SheetTarget) throws -> SheetSnapshot)? = nil,
                write: ((TargetPlan, SheetSnapshot) throws -> Void)? = nil,
                consume: (() throws -> Void)? = nil) {
        self.readSheet = readSheet
        self.write = write
        self.consume = consume
    }
}

public enum TargetStatus: Equatable {
    case previewed
    case written
    case nothingToWrite
}

public struct TargetReport: Equatable {
    public let target: SheetTarget
    public let plannedRows: Int
    public let status: TargetStatus
    /// Plain-text plan description; contains sheet values, so keep it out of logs.
    public let preview: [String]

    public init(target: SheetTarget, plannedRows: Int, status: TargetStatus, preview: [String]) {
        self.target = target
        self.plannedRows = plannedRows
        self.status = status
        self.preview = preview
    }
}

public struct MessageReport: Equatable {
    public let summary: [String]
    public let notes: [String]
    public let targets: [TargetReport]
    public let consumed: Bool
    /// Entries added to a ledger such as a GnuCash book, and their preview lines.
    public let ledgerEntries: Int
    public let ledgerPreview: [String]

    public init(summary: [String], notes: [String], targets: [TargetReport], consumed: Bool,
                ledgerEntries: Int = 0, ledgerPreview: [String] = []) {
        self.summary = summary
        self.notes = notes
        self.targets = targets
        self.consumed = consumed
        self.ledgerEntries = ledgerEntries
        self.ledgerPreview = ledgerPreview
    }
}

/// Errors meaning "this email is not one the use case handles": the email is
/// left in the Inbox and the backlog continues.
public protocol EmailApplicability: Error {
    var leavesEmailInInbox: Bool { get }
}

/// A write failed after earlier targets of the same message were saved and verified.
/// Rerunning is safe: written targets replace their week or skip recorded payments.
public struct PartialWriteError: Error, Equatable, CustomStringConvertible {
    public let written: [SheetTarget]
    public let failed: SheetTarget
    public let reason: String

    public init(written: [SheetTarget], failed: SheetTarget, reason: String) {
        self.written = written
        self.failed = failed
        self.reason = reason
    }

    public var description: String {
        let done = written.isEmpty ? "no sheet was written" : "already written: " + written.map(\.description).joined(separator: ", ")
        return "Writing \(failed) failed (\(reason)); \(done). The message stays in the Inbox."
    }
}

public enum WorkflowError: Error, Equatable, CustomStringConvertible {
    case invalidActions
    case undeclaredTarget

    public var description: String {
        switch self {
        case .invalidActions: return "Consuming mail requires a write, and writing requires reading the sheets"
        case .undeclaredTarget: return "A use case planned a sheet it did not declare"
        }
    }
}

private func describe(_ value: SheetValue) -> String {
    switch value {
    case .date(let date): return String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
    case .number(let number): return "\(number)"
    case .text(let text): return text
    case .empty: return "<blank>"
    }
}

/// Plain-text preview of a plan, naming columns by their headers.
public func describe(_ plan: SheetUpdatePlan, headers: [String]) -> [String] {
    guard !plan.isEmpty else { return ["Nothing to write"] }
    let action: String
    switch plan.placement {
    case .replace(let row): action = "replace row \(row)"
    case .insertAbove(let row): action = "insert \(plan.rows.count) row(s) above row \(row)"
    case .insertBelow(let row): action = "insert \(plan.rows.count) row(s) below row \(row)"
    }
    var lines = ["Plan: \(action)"]
    for (target, row) in zip(plan.targetRows, plan.rows) {
        let cells = row.values.sorted { $0.key < $1.key }.map { column, value in
            let header = column <= headers.count && !headers[column - 1].isEmpty ? headers[column - 1] : "column \(column)"
            return "\(header): \(describe(value))"
        }
        lines.append("  Row \(target): " + cells.joined(separator: " | "))
    }
    return lines
}

/// Summarizes one decoded email and, when actions allow, reads every declared
/// sheet, plans and format-checks all updates, writes them one sheet at a time,
/// and consumes the message only after every sheet is written and verified (or
/// already holds the email's data).
public func processMessage(html: String, useCase: some EmailUseCase,
                           actions: MessageActions) throws -> MessageReport {
    guard actions.consume == nil || actions.write != nil, actions.write == nil || actions.readSheet != nil else {
        throw WorkflowError.invalidActions
    }
    let summary = try useCase.summarize(html: html)
    var declared: [SheetTarget] = []
    for target in useCase.targets where !declared.contains(target) { declared.append(target) }
    guard let readSheet = actions.readSheet, !declared.isEmpty else {
        return MessageReport(summary: summary, notes: [], targets: [], consumed: false)
    }

    var sheets: [SheetTarget: SheetSnapshot] = [:]
    for target in declared { sheets[target] = try readSheet(target) }
    let planned = try useCase.plan(html: html, sheets: sheets)
    for targetPlan in planned.targets {
        guard let sheet = sheets[targetPlan.target] else { throw WorkflowError.undeclaredTarget }
        try targetPlan.update.validateTemplate(in: sheet)
    }
    func report(_ targetPlan: TargetPlan, _ status: TargetStatus) -> TargetReport {
        TargetReport(target: targetPlan.target, plannedRows: targetPlan.update.rows.count, status: status,
                     preview: describe(targetPlan.update, headers: sheets[targetPlan.target]?.headers ?? []))
    }

    guard let write = actions.write else {
        return MessageReport(summary: summary, notes: planned.notes,
                             targets: planned.targets.map { report($0, .previewed) }, consumed: false)
    }
    var written: [SheetTarget] = []
    var reports: [TargetReport] = []
    for targetPlan in planned.targets {
        guard !targetPlan.update.isEmpty else {
            reports.append(report(targetPlan, .nothingToWrite))
            continue
        }
        do {
            try write(targetPlan, sheets[targetPlan.target]!)
        } catch {
            throw PartialWriteError(written: written, failed: targetPlan.target, reason: "\(error)")
        }
        written.append(targetPlan.target)
        reports.append(report(targetPlan, .written))
    }
    try actions.consume?()
    return MessageReport(summary: summary, notes: planned.notes, targets: reports, consumed: actions.consume != nil)
}

import Foundation

public struct MailQuery: Equatable, Sendable {
    public let subjectContains: String
    public let senderContains: String?

    public init(subjectContains: String, senderContains: String?) {
        self.subjectContains = subjectContains
        self.senderContains = senderContains
    }
}

public struct UseCasePlan: Equatable {
    public let update: SheetUpdatePlan
    /// Human-readable notes such as ignored courses or already recorded payments.
    public let notes: [String]

    public init(update: SheetUpdatePlan, notes: [String]) {
        self.update = update
        self.notes = notes
    }
}

/// One kind of email that updates one kind of Numbers sheet.
public protocol MailToNumbersUseCase {
    var mailQuery: MailQuery { get }
    func summarize(html: String) throws -> [String]
    func plan(html: String, sheet: SheetSnapshot) throws -> UseCasePlan
}

public struct MessageActions {
    public var readSheet: (() throws -> SheetSnapshot)?
    public var write: ((SheetUpdatePlan, SheetSnapshot) throws -> Void)?
    public var consume: (() throws -> Void)?

    public init(readSheet: (() throws -> SheetSnapshot)? = nil,
                write: ((SheetUpdatePlan, SheetSnapshot) throws -> Void)? = nil,
                consume: (() throws -> Void)? = nil) {
        self.readSheet = readSheet
        self.write = write
        self.consume = consume
    }
}

public enum MessageOutcome: Equatable {
    case summarized
    case previewed(rows: Int)
    case written(rows: Int)
    case nothingToWrite
}

public enum WorkflowError: Error, Equatable, CustomStringConvertible {
    case invalidActions

    public var description: String { "Consuming mail requires a write, and writing requires reading the sheet" }
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

/// Summarizes one decoded email and, when actions allow, plans, writes, and
/// consumes it. Mail is consumed only after a successful write, or when the plan
/// is empty because the sheet already holds the email's data.
public func processMessage(html: String, useCase: some MailToNumbersUseCase, actions: MessageActions,
                           report: (String) -> Void) throws -> MessageOutcome {
    guard actions.consume == nil || actions.write != nil, actions.write == nil || actions.readSheet != nil else {
        throw WorkflowError.invalidActions
    }
    try useCase.summarize(html: html).forEach(report)
    guard let readSheet = actions.readSheet else { return .summarized }

    let sheet = try readSheet()
    let planned = try useCase.plan(html: html, sheet: sheet)
    planned.notes.forEach(report)
    describe(planned.update, headers: sheet.headers).forEach(report)
    try planned.update.validateTemplate(in: sheet)
    guard let write = actions.write else { return .previewed(rows: planned.update.rows.count) }

    if planned.update.isEmpty {
        try actions.consume?()
        return .nothingToWrite
    }
    try write(planned.update, sheet)
    try actions.consume?()
    return .written(rows: planned.update.rows.count)
}

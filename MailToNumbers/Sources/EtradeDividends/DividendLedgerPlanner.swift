import Foundation
import MailNumbersCore

public enum DividendLedger {
    public static let institution = "E*Trade Financial"
    public static let paymentType = "Dividend or Interest Paid"
    public static let headers = ["Financial Institution", "Account", "Type", "Date", "Security", "Amount Credited"]
}

public enum DividendLedgerError: Error, Equatable {
    case notImplemented
    case unexpectedHeaders
    case unsupportedAccount(String)
    case noTemplateRow
}

public struct DividendLedgerPlan: Equatable {
    public let update: SheetUpdatePlan
    /// Payments whose identical row is already in the ledger.
    public let alreadyRecorded: [DividendPayment]

    public init(update: SheetUpdatePlan, alreadyRecorded: [DividendPayment]) {
        self.update = update
        self.alreadyRecorded = alreadyRecorded
    }
}

public func normalizedAccount(_ mask: String) throws -> String {
    throw DividendLedgerError.notImplemented
}

public func planDividendLedgerUpdate(alert: DividendAlert, sheet: SheetSnapshot) throws -> DividendLedgerPlan {
    throw DividendLedgerError.notImplemented
}

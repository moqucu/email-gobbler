import Foundation
import MailNumbersCore

public struct DividendPayment: Equatable {
    public let security: String
    public let amount: Decimal

    public init(security: String, amount: Decimal) {
        self.security = security
        self.amount = amount
    }
}

public struct DividendAlert: Equatable {
    /// Account as masked in the email, for example "XXXXX-1234".
    public let accountMask: String
    public let paymentDate: CalendarDate
    public let payments: [DividendPayment]

    public init(accountMask: String, paymentDate: CalendarDate, payments: [DividendPayment]) {
        self.accountMask = accountMask
        self.paymentDate = paymentDate
        self.payments = payments
    }
}

public enum DividendAlertError: Error, Equatable {
    case notImplemented
    case unsupportedStructure
    case missingAccount
    case missingPaymentDate
    case invalidPaymentDate(text: String)
    case missingPayments
    case unpairedPayment
    case malformedAmount(text: String)
}

public func parseEtradeDividendAlert(html: String) throws -> DividendAlert {
    throw DividendAlertError.notImplemented
}

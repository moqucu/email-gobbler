import Foundation
import EmailGobblerCore
import SwiftSoup

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

public enum DividendAlertError: Error, Equatable, CustomStringConvertible {
    case unsupportedStructure
    case missingAccount
    case missingPaymentDate
    case invalidPaymentDate(text: String)
    case missingPayments
    case unpairedPayment
    case malformedAmount(text: String)

    public var description: String {
        switch self {
        case .unsupportedStructure: return "Email is not a supported E*TRADE dividend alert"
        case .missingAccount: return "Alert has no single account"
        case .missingPaymentDate: return "Alert has no payment date"
        case .invalidPaymentDate(let text): return "Alert payment date is invalid: \(text)"
        case .missingPayments: return "Alert lists no payments"
        case .unpairedPayment: return "Alert has a security without an amount or an amount without a security"
        case .malformedAmount(let text): return "Alert amount is malformed: \(text)"
        }
    }
}

private func collapsed(_ text: String) -> String {
    text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

/// Text after a bold label up to the next bold label or line break.
private func labelValue(after strong: Element) -> String {
    var parts: [String] = []
    var node = strong.nextSibling()
    while let current = node {
        if let element = current as? Element {
            let tag = element.tagName().lowercased()
            if tag == "br" || tag == "strong" { break }
            parts.append((try? element.text()) ?? "")
        } else if let text = current as? TextNode {
            parts.append(text.text())
        }
        node = current.nextSibling()
    }
    return collapsed(parts.joined(separator: " "))
}

private func amount(_ text: String) throws -> Decimal {
    let grouped = "^\\$[0-9]{1,3}(,[0-9]{3})*(\\.[0-9]{2})?$"
    let plain = "^\\$[0-9]+(\\.[0-9]{2})?$"
    guard text.range(of: grouped, options: .regularExpression) != nil
            || text.range(of: plain, options: .regularExpression) != nil,
          let value = Decimal(string: text.dropFirst().replacingOccurrences(of: ",", with: ""),
                              locale: Locale(identifier: "en_US_POSIX")) else {
        throw DividendAlertError.malformedAmount(text: text)
    }
    return value
}

/// Extracts a "Dividend or interest paid" alert from its decoded HTML. Only the
/// visible `td.body-content` cell is read; the hidden preview text is ignored.
public func parseEtradeDividendAlert(html: String) throws -> DividendAlert {
    guard let document = try? SwiftSoup.parse(html),
          let body = try? document.select("td.body-content").first() else {
        throw DividendAlertError.unsupportedStructure
    }

    var labels: [(label: String, value: String)] = []
    for strong in (try? body.select("strong").array()) ?? [] {
        let label = collapsed((try? strong.text()) ?? "")
        labels.append((label, labelValue(after: strong)))
    }

    let accounts = labels.filter { $0.label == "Account:" }.map(\.value)
    guard accounts.count == 1, let account = accounts.first, !account.isEmpty else {
        throw DividendAlertError.missingAccount
    }

    let bodyText = collapsed((try? body.text()) ?? "")
    guard let sentence = bodyText.range(of: "payment\\(s\\) on [^ ]+?\\.( |$)", options: .regularExpression) else {
        throw DividendAlertError.missingPaymentDate
    }
    let dateText = String(bodyText[sentence].dropFirst("payment(s) on ".count))
        .trimmingCharacters(in: .whitespaces).dropLast()
    let parts = dateText.split(separator: "-").compactMap { Int($0) }
    guard dateText.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil, parts.count == 3,
          let paymentDate = try? CalendarDate(year: parts[0], month: parts[1], day: parts[2]) else {
        throw DividendAlertError.invalidPaymentDate(text: String(dateText))
    }

    let paymentLabels = labels.filter { $0.label == "Security:" || $0.label == "Amount Credited:" }
    guard !paymentLabels.isEmpty else { throw DividendAlertError.missingPayments }
    guard paymentLabels.count.isMultiple(of: 2) else { throw DividendAlertError.unpairedPayment }
    var payments: [DividendPayment] = []
    for index in stride(from: 0, to: paymentLabels.count, by: 2) {
        let security = paymentLabels[index]
        let credited = paymentLabels[index + 1]
        guard security.label == "Security:", credited.label == "Amount Credited:", !security.value.isEmpty else {
            throw DividendAlertError.unpairedPayment
        }
        payments.append(DividendPayment(security: security.value, amount: try amount(credited.value)))
    }
    return DividendAlert(accountMask: account, paymentDate: paymentDate, payments: payments)
}

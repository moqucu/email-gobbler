import Foundation
import os

/// Writes run events to the unified log. Events never carry email content.
public func unifiedLog(_ event: RunLogEvent) {
    let logger = Logger(subsystem: "com.moqucu.MailToNumbers", category: event.useCase.rawValue)
    logger.notice("\(event.stage, privacy: .public) \(event.outcome, privacy: .public) message=\(event.messageID ?? "-", privacy: .private(mask: .hash))")
}

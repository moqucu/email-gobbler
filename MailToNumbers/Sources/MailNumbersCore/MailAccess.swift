import Foundation

/// Lists matching Mail Inbox messages, oldest first.
public func listInboxMessages(_ query: MailQuery) throws -> [MailMessageRef] {
    guard !query.subjectContains.isEmpty,
          !(query.subjectContains + (query.senderContains ?? "")).contains(where: { "\n\r".contains($0) }) else {
        throw MailConsumptionError.automation("Mail query cannot be empty or contain line breaks")
    }
    let senderFilter = query.senderContains.map { " and sender contains \(appleScriptString($0))" } ?? ""
    let result = try runAppleScript("""
    tell application "Mail"
        set matches to messages of inbox whose subject contains \(appleScriptString(query.subjectContains))\(senderFilter)
        set nowDate to current date
        set outLines to {}
        repeat with m in matches
            set end of outLines to ((id of m) as text) & tab & (id of account of mailbox of m) & tab & (message id of m) & tab & ((((date received of m) - nowDate) as integer) as text)
        end repeat
        set AppleScript's text item delimiters to linefeed
        return outLines as text
    end tell
    """)
    return try parseMailListing(result.stringValue ?? "")
}

/// Fetches a listed message's source after confirming its identity.
public func fetchMailMessage(_ ref: MailMessageRef) throws -> FetchedMailMessage {
    let result = try runAppleScript("""
    tell application "Mail"
        set matches to messages of inbox whose id is \(ref.id)
        if (count of matches) is not 1 then error "Message is no longer in the Inbox"
        set chosen to item 1 of matches
        if id of account of mailbox of chosen is not \(appleScriptString(ref.accountID)) then error "Message account changed"
        if message id of chosen is not \(appleScriptString(ref.rfcMessageID)) then error "Message identity changed"
        return source of chosen
    end tell
    """)
    guard let source = result.stringValue else { throw AutomationError.unexpectedResult }
    return FetchedMailMessage(source: Data(source.utf8), id: ref.id, accountID: ref.accountID, rfcMessageID: ref.rfcMessageID)
}

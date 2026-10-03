import Foundation

public struct FetchedMailMessage {
    public let source: Data
    public let id: Int32
    public let accountID: String
    public let rfcMessageID: String

    public init(source: Data, id: Int32, accountID: String, rfcMessageID: String) {
        self.source = source
        self.id = id
        self.accountID = accountID
        self.rfcMessageID = rfcMessageID
    }
}

public enum MailConsumptionError: Error, CustomStringConvertible {
    case messageChanged
    case automation(String)

    public var description: String {
        switch self {
        case .messageChanged: return "The selected Mail message changed or left the iCloud Inbox"
        case .automation(let message): return "Mail consumption failed: \(message)"
        }
    }
}

public func consumeMailMessage(_ message: FetchedMailMessage) throws {
    let script = """
    tell application "Mail"
        set a to first account whose id is \(appleScriptString(message.accountID))
        if server name of a is not "imap.mail.me.com" then error "Selected account is not iCloud Mail"
        set matches to messages of inbox whose id is \(message.id)
        if (count of matches) is not 1 then error "Selected message is not in Inbox"
        set chosen to item 1 of matches
        if id of account of mailbox of chosen is not \(appleScriptString(message.accountID)) then error "Message account changed"
        if message id of chosen is not \(appleScriptString(message.rfcMessageID)) then error "Message identity changed"
        set archiveBox to mailbox "Archive" of a
        set read status of chosen to true
        move chosen to archiveBox
        set archivedMatches to messages of archiveBox whose message id is \(appleScriptString(message.rfcMessageID))
        if (count of archivedMatches) is 0 then error "Message not found in iCloud Archive after move"
        if read status of item 1 of archivedMatches is false then error "Archived message is unread"
        return "archived"
    end tell
    """
    _ = try runAppleScript(script)
}

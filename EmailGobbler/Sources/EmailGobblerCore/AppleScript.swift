import Foundation

public func appleScriptString(_ text: String) -> String {
    "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

import Foundation

enum MailDecodeError: Error {
    case malformedMessage
    case unsupportedEncoding(String)
    case unsupportedCharset(String)
    case missingHTML
}

enum MailDecoder {
    static func html(from message: Data) throws -> String {
        guard let html = try htmlPart(in: message) else { throw MailDecodeError.missingHTML }
        return html
    }

    private static func htmlPart(in message: Data) throws -> String? {
        guard let split = headerBody(message) else { throw MailDecodeError.malformedMessage }
        let headers = parseHeaders(split.headers)
        let contentType = headers["content-type"] ?? "text/plain"
        let lowerType = contentType.lowercased()

        if lowerType.hasPrefix("multipart/") {
            guard let boundary = parameter("boundary", in: contentType), !boundary.isEmpty else {
                throw MailDecodeError.malformedMessage
            }
            for part in parts(in: split.body, boundary: boundary) {
                if let html = try htmlPart(in: part) { return html }
            }
            return nil
        }

        guard lowerType.hasPrefix("text/html") else { return nil }
        let encoded = split.body
        let transfer = (headers["content-transfer-encoding"] ?? "7bit")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let decoded: Data
        switch transfer {
        case "base64":
            let compact = encoded.filter { ![9, 10, 13, 32].contains($0) }
            guard let value = Data(base64Encoded: compact) else { throw MailDecodeError.malformedMessage }
            decoded = value
        case "quoted-printable":
            decoded = try quotedPrintable(encoded)
        case "7bit", "8bit", "binary":
            decoded = encoded
        default:
            throw MailDecodeError.unsupportedEncoding(transfer)
        }

        let charset = (parameter("charset", in: contentType) ?? "us-ascii").lowercased()
        let stringEncoding: String.Encoding
        switch charset {
        case "utf-8", "utf8", "us-ascii": stringEncoding = .utf8
        case "iso-8859-1", "latin1": stringEncoding = .isoLatin1
        case "windows-1252": stringEncoding = .windowsCP1252
        default: throw MailDecodeError.unsupportedCharset(charset)
        }
        guard let text = String(data: decoded, encoding: stringEncoding) else {
            throw MailDecodeError.malformedMessage
        }
        return text
    }

    private static func headerBody(_ data: Data) -> (headers: Data, body: Data)? {
        if let range = data.range(of: Data("\r\n\r\n".utf8)) {
            return (data[..<range.lowerBound], data[range.upperBound...])
        }
        if let range = data.range(of: Data("\n\n".utf8)) {
            return (data[..<range.lowerBound], data[range.upperBound...])
        }
        return nil
    }

    private static func parseHeaders(_ data: Data) -> [String: String] {
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
        var result: [String: String] = [:]
        var key: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if (line.first == " " || line.first == "\t"), let current = key {
                result[current, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                let name = line[..<colon].lowercased()
                key = name
                result[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }

    private static func parameter(_ name: String, in header: String) -> String? {
        for field in header.split(separator: ";").dropFirst() {
            let halves = field.split(separator: "=", maxSplits: 1)
            guard halves.count == 2, halves[0].trimmingCharacters(in: .whitespaces).lowercased() == name else { continue }
            return halves[1].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    private static func parts(in body: Data, boundary: String) -> [Data] {
        let marker = Data(("--" + boundary).utf8)
        var found: [Data] = []
        var offset = body.startIndex
        while let range = body.range(of: marker, in: offset..<body.endIndex) {
            let after = range.upperBound
            let atLineStart = range.lowerBound == body.startIndex || body[range.lowerBound - 1] == 10
            let hasLineEnd = body[after...].starts(with: [13, 10]) || body[after...].starts(with: [10])
                || body[after...].starts(with: [45, 45])
            guard atLineStart && hasLineEnd else {
                offset = after
                continue
            }
            if body[after...].starts(with: [45, 45]) { break }
            var nextOffset = after
            var next: Range<Data.Index>?
            while let candidate = body.range(of: marker, in: nextOffset..<body.endIndex) {
                let candidateAfter = candidate.upperBound
                if (candidate.lowerBound == body.startIndex || body[candidate.lowerBound - 1] == 10)
                    && (body[candidateAfter...].starts(with: [13, 10])
                        || body[candidateAfter...].starts(with: [10])
                        || body[candidateAfter...].starts(with: [45, 45])) {
                    next = candidate
                    break
                }
                nextOffset = candidateAfter
            }
            guard let next else { break }
            var start = after
            if body[start...].starts(with: [13, 10]) { start += 2 }
            else if body[start...].starts(with: [10]) { start += 1 }
            var end = next.lowerBound
            if end >= 2 && body[(end - 2)..<end].elementsEqual([13, 10]) { end -= 2 }
            else if end >= 1 && body[end - 1] == 10 { end -= 1 }
            if start <= end { found.append(body[start..<end]) }
            offset = next.lowerBound
            if offset == range.lowerBound { break }
        }
        return found
    }

    private static func quotedPrintable(_ data: Data) throws -> Data {
        let bytes = Array(data)
        var result = Data()
        var index = 0
        while index < bytes.count {
            if bytes[index] == 61 {
                if index + 2 < bytes.count && bytes[index + 1] == 13 && bytes[index + 2] == 10 {
                    index += 3
                    continue
                }
                if index + 1 < bytes.count && bytes[index + 1] == 10 {
                    index += 2
                    continue
                }
                guard index + 2 < bytes.count,
                      let high = hex(bytes[index + 1]), let low = hex(bytes[index + 2]) else {
                    throw MailDecodeError.malformedMessage
                }
                result.append(high * 16 + low)
                index += 3
            } else {
                result.append(bytes[index])
                index += 1
            }
        }
        return result
    }

    private static func hex(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }
}

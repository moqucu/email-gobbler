import Foundation

/// gzip framing (RFC 1952) around the raw DEFLATE codec Foundation provides.
public enum Gzip {
    private static let crcTable: [UInt32] = (0..<256).map { index in
        var crc = UInt32(index)
        for _ in 0..<8 { crc = crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
        return crc
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    private static func littleEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)]
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    public static func isCompressed(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
    }

    public static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else {
            throw GnuCashError.corruptCompressedData
        }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 {
            guard offset + 2 <= bytes.count else { throw GnuCashError.corruptCompressedData }
            offset += 2 + (Int(bytes[offset]) | Int(bytes[offset + 1]) << 8)
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {
            while offset < bytes.count && bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }
        guard offset <= bytes.count - 8 else { throw GnuCashError.corruptCompressedData }

        let deflated = Data(bytes[offset..<(bytes.count - 8)])
        guard let inflated = try? (deflated as NSData).decompressed(using: .zlib) as Data,
              crc32(inflated) == readUInt32(bytes, bytes.count - 8),
              UInt32(truncatingIfNeeded: inflated.count) == readUInt32(bytes, bytes.count - 4) else {
            throw GnuCashError.corruptCompressedData
        }
        return inflated
    }

    public static func compress(_ data: Data) -> Data {
        let deflated = (try? (data as NSData).compressed(using: .zlib) as Data) ?? Data()
        var output = Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 3])
        output.append(deflated)
        output.append(contentsOf: littleEndian(crc32(data)))
        output.append(contentsOf: littleEndian(UInt32(truncatingIfNeeded: data.count)))
        return output
    }
}

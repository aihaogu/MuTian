import CoreFoundation
import Foundation

enum TextFileLoader {
    static func load(from url: URL) throws -> String {
        try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> String {
        if data.isEmpty { return "" }
        let bomEncodings: [([UInt8], String.Encoding)] = [
            ([0xFF, 0xFE, 0x00, 0x00], .utf32LittleEndian),
            ([0x00, 0x00, 0xFE, 0xFF], .utf32BigEndian),
            ([0xFF, 0xFE], .utf16LittleEndian),
            ([0xFE, 0xFF], .utf16BigEndian),
            ([0xEF, 0xBB, 0xBF], .utf8)
        ]
        for (bom, encoding) in bomEncodings where data.starts(with: bom) {
            if let text = String(data: data.dropFirst(bom.count), encoding: encoding) { return text }
            throw DecodingError.unsupportedEncoding
        }
        if let text = String(data: data, encoding: .utf8), !text.contains("\0") { return text }
        // Check zero-byte placement before trying legacy encodings for BOM-less UTF-16.
        if data.count.isMultiple(of: 2) {
            let bytes = Array(data.prefix(4096))
            for (offset, encoding) in [(1, String.Encoding.utf16LittleEndian), (0, .utf16BigEndian)] {
                let zeros = stride(from: offset, to: bytes.count, by: 2).filter { bytes[$0] == 0 }.count
                if zeros > bytes.count / 8, let text = String(data: data, encoding: encoding) { return text }
            }
        }
        for encoding in [CFStringEncodings.GB_18030_2000, .big5] {
            let converted = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue)))
            if let text = String(data: data, encoding: converted), !text.contains("\0") { return text }
        }
        throw DecodingError.unsupportedEncoding
    }

    private enum DecodingError: LocalizedError {
        case unsupportedEncoding
        var errorDescription: String? { "无法识别文本编码。请将文件保存为 UTF-8 后重试。" }
    }
}

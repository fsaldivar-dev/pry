import Foundation
import Compression

/// Decompresses HTTP response bodies for display purposes.
/// Supports gzip and deflate. Brotli (br) is not supported.
public enum BodyDecompressor {
    public static func decompress(_ data: Data, encoding: String?) -> Data? {
        guard let enc = encoding?.lowercased().trimmingCharacters(in: .whitespaces) else { return nil }
        if enc == "gzip" || enc == "x-gzip" {
            return inflateGzip(data)
        }
        if enc == "deflate" {
            return inflateRaw(data) ?? inflateZlib(data)
        }
        return nil
    }

    /// gzip frame: 10-byte header (with optional extras) + raw deflate + 8-byte trailer.
    private static func inflateGzip(_ data: Data) -> Data? {
        guard data.count > 18 else { return nil }
        guard data[0] == 0x1f, data[1] == 0x8b else { return nil }
        let flg = data[3]
        var offset = 10

        // FEXTRA
        if flg & 0x04 != 0 {
            guard data.count > offset + 2 else { return nil }
            let xlen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + xlen
        }
        // FNAME
        if flg & 0x08 != 0 {
            while offset < data.count, data[offset] != 0 { offset += 1 }
            offset += 1
        }
        // FCOMMENT
        if flg & 0x10 != 0 {
            while offset < data.count, data[offset] != 0 { offset += 1 }
            offset += 1
        }
        // FHCRC
        if flg & 0x02 != 0 { offset += 2 }

        let trailerSize = 8
        guard offset < data.count - trailerSize else { return nil }
        let payload = data.subdata(in: offset..<(data.count - trailerSize))
        return inflateRaw(payload)
    }

    /// Raw deflate (no zlib header).
    private static func inflateRaw(_ data: Data) -> Data? {
        let bufferSize = max(data.count * 4, 65536)
        return data.withUnsafeBytes { (inBuf: UnsafeRawBufferPointer) -> Data? in
            guard let inBase = inBuf.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let outBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { outBuffer.deallocate() }

            var result = Data()
            var totalConsumed = 0
            while totalConsumed < data.count {
                let consumed = compression_decode_buffer(
                    outBuffer, bufferSize,
                    inBase.advanced(by: totalConsumed), data.count - totalConsumed,
                    nil, COMPRESSION_ZLIB
                )
                if consumed == 0 { return result.isEmpty ? nil : result }
                result.append(outBuffer, count: consumed)
                // compression_decode_buffer returns bytes written, not consumed — one-shot API.
                // For our use, one call inflates the whole stream.
                return result
            }
            return result.isEmpty ? nil : result
        }
    }

    /// Deflate with zlib header (RFC 1950): skip 2-byte header before raw inflate.
    private static func inflateZlib(_ data: Data) -> Data? {
        guard data.count > 2 else { return nil }
        let payload = data.subdata(in: 2..<data.count)
        return inflateRaw(payload)
    }
}

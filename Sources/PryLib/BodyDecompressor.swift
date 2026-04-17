import Foundation
#if canImport(Compression)
import Compression
#endif

/// Decompresses HTTP response bodies for display purposes.
///
/// Supported encodings:
///   - gzip / x-gzip        via Apple's Compression framework (raw deflate + gzip frame)
///   - deflate              via Apple's Compression framework (tries raw first, then zlib-wrapped)
///   - br (brotli)          via subprocess to `/usr/bin/brotli` (best-effort)
///
/// Brotli strategy: Apple's Compression framework does NOT expose brotli, and vendoring a
/// pure-Swift brotli decoder would add >100 KB of dictionary tables + decoder logic for a
/// debugging-only code path. Instead we shell out to the system `brotli` binary with a short
/// timeout. If the binary is missing we return nil and callers fall back to a sentinel string
/// ("[body compressed with brotli — install `brew install brotli` to decompress]") so users
/// see a clear message instead of garbled bytes.
///
/// On Linux (no Compression framework) this type returns nil for everything — callers fall
/// back to raw bytes.
public enum BodyDecompressor {
    /// Sentinel emitted by callers when brotli decompression is unavailable.
    /// Exposed so HTTPInterceptor / ConnectHandler can use the same message.
    public static let brotliUnavailableMessage =
        "[body compressed with brotli — install `brew install brotli` to decompress]"

    /// Returns true if the Content-Encoding value names a brotli stream.
    public static func isBrotli(_ encoding: String?) -> Bool {
        guard let enc = encoding?.lowercased().trimmingCharacters(in: .whitespaces) else { return false }
        return enc == "br" || enc == "brotli"
    }

    public static func decompress(_ data: Data, encoding: String?) -> Data? {
        guard let enc = encoding?.lowercased().trimmingCharacters(in: .whitespaces) else { return nil }

        if enc == "br" || enc == "brotli" {
            return inflateBrotli(data)
        }

        #if canImport(Compression)
        if enc == "gzip" || enc == "x-gzip" {
            return inflateGzip(data)
        }
        if enc == "deflate" {
            return inflateRaw(data) ?? inflateZlib(data)
        }
        return nil
        #else
        return nil
        #endif
    }

    // MARK: - Brotli (subprocess)

    /// Decompress a brotli stream by piping it through `/usr/bin/brotli -d`.
    /// Returns nil if the binary is missing, the process fails, or we time out.
    /// This is intentionally a best-effort path — it's only used for displaying bodies
    /// in the proxy UI, never on the wire.
    static func inflateBrotli(_ data: Data) -> Data? {
        #if os(macOS) || os(Linux)
        let candidates = [
            "/opt/homebrew/bin/brotli",
            "/usr/local/bin/brotli",
            "/usr/bin/brotli",
        ]
        guard let binary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-d", "-c"] // decode, write to stdout

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        // Write input on a background queue so we don't deadlock if the pipe buffer fills.
        DispatchQueue.global().async {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
            try? stdinPipe.fileHandleForWriting.close()
        }

        // 3-second timeout guard.
        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0, execute: timeoutWorkItem)

        let output = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        timeoutWorkItem.cancel()

        guard process.terminationStatus == 0, !output.isEmpty else {
            return nil
        }
        return output
        #else
        return nil
        #endif
    }

    // MARK: - gzip / deflate (Apple Compression framework)

    #if canImport(Compression)

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
    #endif
}

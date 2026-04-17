import Foundation
#if canImport(Compression)
import Compression
#endif

/// Decompresses HTTP response bodies for display purposes.
///
/// Supported encodings (Apple platforms via `Compression` framework):
///   - gzip / x-gzip  — RFC 1952 gzip frame parsing + raw deflate
///   - deflate        — raw DEFLATE first, zlib-wrapped (RFC 1950) fallback
///   - br / brotli    — native `COMPRESSION_BROTLI` (disponible desde macOS 12 / iOS 15)
///
/// Todo embedded en el binario — no requiere binarios externos ni dependencias.
/// En Linux (sin `Compression` framework) retorna nil para todo; los callers
/// muestran los bytes crudos.
public enum BodyDecompressor {
    /// Retorna `true` si el valor de Content-Encoding nombra un stream brotli.
    public static func isBrotli(_ encoding: String?) -> Bool {
        guard let enc = encoding?.lowercased().trimmingCharacters(in: .whitespaces) else { return false }
        return enc == "br" || enc == "brotli"
    }

    public static func decompress(_ data: Data, encoding: String?) -> Data? {
        guard let enc = encoding?.lowercased().trimmingCharacters(in: .whitespaces) else { return nil }

        #if canImport(Compression)
        if enc == "br" || enc == "brotli" {
            return inflateBrotli(data)
        }
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

    #if canImport(Compression)

    // MARK: - Brotli (nativo, Compression framework)

    /// Inflate usando `COMPRESSION_BROTLI` — nativo de Apple desde macOS 12 / iOS 15.
    /// No requiere binarios externos ni dependencias.
    private static func inflateBrotli(_ data: Data) -> Data? {
        // Brotli suele comprimir 3-5x para JSON. 16x nos da margen holgado.
        let initialBufferSize = max(data.count * 16, 131072)
        return decodeOneShot(data, algorithm: COMPRESSION_BROTLI, initialBufferSize: initialBufferSize)
    }

    // MARK: - gzip / deflate

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
        return decodeOneShot(data, algorithm: COMPRESSION_ZLIB, initialBufferSize: bufferSize)
    }

    /// Deflate with zlib header (RFC 1950): skip 2-byte header before raw inflate.
    private static func inflateZlib(_ data: Data) -> Data? {
        guard data.count > 2 else { return nil }
        let payload = data.subdata(in: 2..<data.count)
        return inflateRaw(payload)
    }

    // MARK: - Helper compartido

    /// One-shot decode vía `compression_decode_buffer`. Reintenta con buffer más grande
    /// si el resultado llenó el output exactamente (indicativo de truncación).
    private static func decodeOneShot(
        _ data: Data,
        algorithm: compression_algorithm,
        initialBufferSize: Int
    ) -> Data? {
        var bufferSize = initialBufferSize
        // Hasta 3 intentos con buffer doble si sospechamos truncación.
        for _ in 0..<3 {
            let result: Data? = data.withUnsafeBytes { (inBuf: UnsafeRawBufferPointer) -> Data? in
                guard let inBase = inBuf.bindMemory(to: UInt8.self).baseAddress else { return nil }
                let outBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { outBuffer.deallocate() }

                let written = compression_decode_buffer(
                    outBuffer, bufferSize,
                    inBase, data.count,
                    nil, algorithm
                )
                if written == 0 { return nil }
                // Si llenó el buffer exacto, puede haber truncado — reintentar con más.
                if written == bufferSize { return Data() } // sentinel vacío = reintentar
                return Data(bytes: outBuffer, count: written)
            }

            if let data = result, !data.isEmpty { return data }
            if result == nil { return nil } // fallo real del codec
            // Truncación sospechada — reintentar con buffer doble.
            bufferSize *= 2
        }
        return nil
    }
    #endif
}

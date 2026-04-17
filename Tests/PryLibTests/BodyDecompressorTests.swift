import XCTest
@testable import PryLib

final class BodyDecompressorTests: XCTestCase {
    // Payload compressed with each encoding to produce: {"ok":true,"msg":"hello brotli"}
    private static let payload = #"{"ok":true,"msg":"hello brotli"}"#

    // echo -n '{"ok":true,"msg":"hello brotli"}' | gzip | base64
    private static let gzipB64 =
        "H4sIAEZ44WkAA6tWys9WsiopKk3VUcotTleyUspIzcnJV0gqyi/JyVSqBQAd4eroIAAAAA=="

    // Python: zlib.compressobj(wbits=-15) — raw deflate, no zlib header/trailer.
    // This is what HTTP `Content-Encoding: deflate` is supposed to carry in practice.
    private static let deflateRawB64 =
        "q1bKz1ayKikqTdVRyi1OV7JSykjNyclXSCrKL8nJVKoFAA=="

    // echo -n '{"ok":true,"msg":"hello brotli"}' | brotli --stdout | base64
    private static let brotliB64 =
        "jw+AeyJvayI6dHJ1ZSwibXNnIjoiaGVsbG8gYnJvdGxpIn0D"

    // MARK: gzip

    func testGzipDecompressesToOriginal() throws {
        #if !canImport(Compression)
        throw XCTSkip("Compression framework only available on Apple platforms")
        #else
        let data = try XCTUnwrap(Data(base64Encoded: Self.gzipB64))
        let inflated = try XCTUnwrap(BodyDecompressor.decompress(data, encoding: "gzip"))
        XCTAssertEqual(String(data: inflated, encoding: .utf8), Self.payload)
        #endif
    }

    func testGzipAlsoAcceptsXGzip() throws {
        #if !canImport(Compression)
        throw XCTSkip("Compression framework only available on Apple platforms")
        #else
        let data = try XCTUnwrap(Data(base64Encoded: Self.gzipB64))
        let inflated = try XCTUnwrap(BodyDecompressor.decompress(data, encoding: "x-gzip"))
        XCTAssertEqual(String(data: inflated, encoding: .utf8), Self.payload)
        #endif
    }

    // MARK: deflate

    func testDeflateDecompressesToOriginal() throws {
        #if !canImport(Compression)
        throw XCTSkip("Compression framework only available on Apple platforms")
        #else
        let data = try XCTUnwrap(Data(base64Encoded: Self.deflateRawB64))
        let inflated = try XCTUnwrap(BodyDecompressor.decompress(data, encoding: "deflate"))
        XCTAssertEqual(String(data: inflated, encoding: .utf8), Self.payload)
        #endif
    }

    // MARK: brotli

    /// Brotli descompresión nativa via Apple's Compression framework
    /// (COMPRESSION_BROTLI, disponible desde macOS 12 / iOS 15).
    /// No requiere binarios externos.
    func testBrotliDecompressesToOriginal() throws {
        #if !canImport(Compression)
        throw XCTSkip("Compression framework only available on Apple platforms")
        #else
        let data = try XCTUnwrap(Data(base64Encoded: Self.brotliB64))
        let inflated = try XCTUnwrap(BodyDecompressor.decompress(data, encoding: "br"))
        XCTAssertEqual(String(data: inflated, encoding: .utf8), Self.payload)
        #endif
    }

    func testBrotliAcceptsAltSpelling() throws {
        #if !canImport(Compression)
        throw XCTSkip("Compression framework only available on Apple platforms")
        #else
        let data = try XCTUnwrap(Data(base64Encoded: Self.brotliB64))
        let inflated = try XCTUnwrap(BodyDecompressor.decompress(data, encoding: "brotli"))
        XCTAssertEqual(String(data: inflated, encoding: .utf8), Self.payload)
        #endif
    }

    // MARK: unknown / malformed

    func testUnknownEncodingReturnsNil() {
        let data = Data([0x00, 0x01, 0x02])
        XCTAssertNil(BodyDecompressor.decompress(data, encoding: "snappy"))
    }

    func testNilEncodingReturnsNil() {
        let data = Data([0x00, 0x01, 0x02])
        XCTAssertNil(BodyDecompressor.decompress(data, encoding: nil))
    }

    func testIsBrotliHelper() {
        XCTAssertTrue(BodyDecompressor.isBrotli("br"))
        XCTAssertTrue(BodyDecompressor.isBrotli("BR"))
        XCTAssertTrue(BodyDecompressor.isBrotli("  brotli  "))
        XCTAssertFalse(BodyDecompressor.isBrotli("gzip"))
        XCTAssertFalse(BodyDecompressor.isBrotli(nil))
    }

}

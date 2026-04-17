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
        let data = try XCTUnwrap(Data(base64Encoded: Self.gzipB64))
        let inflated = try XCTUnwrap(BodyDecompressor.decompress(data, encoding: "gzip"))
        XCTAssertEqual(String(data: inflated, encoding: .utf8), Self.payload)
    }

    func testGzipAlsoAcceptsXGzip() throws {
        let data = try XCTUnwrap(Data(base64Encoded: Self.gzipB64))
        let inflated = try XCTUnwrap(BodyDecompressor.decompress(data, encoding: "x-gzip"))
        XCTAssertEqual(String(data: inflated, encoding: .utf8), Self.payload)
    }

    // MARK: deflate

    func testDeflateDecompressesToOriginal() throws {
        let data = try XCTUnwrap(Data(base64Encoded: Self.deflateRawB64))
        let inflated = try XCTUnwrap(BodyDecompressor.decompress(data, encoding: "deflate"))
        XCTAssertEqual(String(data: inflated, encoding: .utf8), Self.payload)
    }

    // MARK: brotli

    /// Brotli decompression depends on the `brotli` binary being present on PATH.
    /// On CI runners that have it (macos-14 typically does via Homebrew) the test runs;
    /// otherwise it's skipped rather than failing, since brotli support is best-effort.
    func testBrotliDecompressesToOriginal() throws {
        guard brotliBinaryAvailable() else {
            throw XCTSkip("brotli binary not installed — skipping best-effort test")
        }
        let data = try XCTUnwrap(Data(base64Encoded: Self.brotliB64))
        let inflated = try XCTUnwrap(BodyDecompressor.decompress(data, encoding: "br"))
        XCTAssertEqual(String(data: inflated, encoding: .utf8), Self.payload)
    }

    func testBrotliAcceptsAltSpelling() throws {
        guard brotliBinaryAvailable() else {
            throw XCTSkip("brotli binary not installed — skipping best-effort test")
        }
        let data = try XCTUnwrap(Data(base64Encoded: Self.brotliB64))
        let inflated = try XCTUnwrap(BodyDecompressor.decompress(data, encoding: "brotli"))
        XCTAssertEqual(String(data: inflated, encoding: .utf8), Self.payload)
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

    // MARK: helpers

    private func brotliBinaryAvailable() -> Bool {
        let candidates = ["/opt/homebrew/bin/brotli", "/usr/local/bin/brotli", "/usr/bin/brotli"]
        return candidates.contains(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }
}

import XCTest
@testable import PryLib

final class HARImporterTests: XCTestCase {
    private let testPath = "/tmp/pry-test-import.har"

    override func setUp() {
        super.setUp()
        RequestStore.shared.clear()
        try? FileManager.default.removeItem(atPath: testPath)
    }

    override func tearDown() {
        RequestStore.shared.clear()
        try? FileManager.default.removeItem(atPath: testPath)
        super.tearDown()
    }

    func testImportHARWithRequests() throws {
        let har = """
        {"log":{"version":"1.2","creator":{"name":"Test"},"entries":[
            {"startedDateTime":"2026-01-01T00:00:00Z","time":0,
             "request":{"method":"GET","url":"http://example.com/api/users","httpVersion":"HTTP/1.1","headers":[],"queryString":[],"headersSize":-1,"bodySize":0},
             "response":{"status":200,"statusText":"OK","httpVersion":"HTTP/1.1","headers":[],"content":{"size":0,"mimeType":"application/json","text":"{}"},"headersSize":-1,"bodySize":0,"redirectURL":""},
             "cache":{},"timings":{"send":0,"wait":0,"receive":0}}
        ]}}
        """
        try har.write(toFile: testPath, atomically: true, encoding: .utf8)
        try HARImporter.importFromFile(path: testPath)
        XCTAssertEqual(RequestStore.shared.count(), 1)
        let all = RequestStore.shared.getAll()
        XCTAssertEqual(all[0].method, "GET")
    }

    func testImportHARPreservesMethod() throws {
        let har = """
        {"log":{"version":"1.2","creator":{"name":"Test"},"entries":[
            {"startedDateTime":"2026-01-01T00:00:00Z","time":0,
             "request":{"method":"POST","url":"http://example.com/api","httpVersion":"HTTP/1.1","headers":[{"name":"Content-Type","value":"application/json"}],"queryString":[],"headersSize":-1,"bodySize":0},
             "response":{"status":201,"statusText":"Created","httpVersion":"HTTP/1.1","headers":[],"content":{"size":0,"mimeType":"","text":""},"headersSize":-1,"bodySize":0,"redirectURL":""},
             "cache":{},"timings":{"send":0,"wait":0,"receive":0}}
        ]}}
        """
        try har.write(toFile: testPath, atomically: true, encoding: .utf8)
        try HARImporter.importFromFile(path: testPath)
        let all = RequestStore.shared.getAll()
        XCTAssertEqual(all[0].method, "POST")
        XCTAssertEqual(all[0].statusCode, 201)
    }

    func testImportHAREmptyEntries() throws {
        let har = "{\"log\":{\"version\":\"1.2\",\"creator\":{\"name\":\"Test\"},\"entries\":[]}}"
        try har.write(toFile: testPath, atomically: true, encoding: .utf8)
        try HARImporter.importFromFile(path: testPath)
        XCTAssertEqual(RequestStore.shared.count(), 0)
    }

    func testImportInvalidJSON() {
        let bad = "not json"
        try? bad.write(toFile: testPath, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try HARImporter.importFromFile(path: testPath))
    }
}

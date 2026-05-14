import XCTest
@testable import PryLib

final class DiffToolTests: XCTestCase {
    private func makeRequest(method: String = "GET", url: String = "/api", host: String = "example.com", headers: [(String, String)] = [], body: String? = nil, statusCode: UInt? = nil, responseBody: String? = nil) -> RequestStore.CapturedRequest {
        RequestStore.CapturedRequest(method: method, url: url, host: host, appIcon: "🌐", appName: "test", requestHeaders: headers, requestBody: body, statusCode: statusCode, responseBody: responseBody)
    }

    func testIdenticalRequests() {
        let req = makeRequest()
        let diff = DiffTool.diff(req1: req, req2: req)
        XCTAssertTrue(diff.allSatisfy { if case .same = $0 { return true }; return false })
    }

    func testDifferentMethod() {
        let req1 = makeRequest(method: "GET")
        let req2 = makeRequest(method: "POST")
        let diff = DiffTool.diff(req1: req1, req2: req2)
        let hasMethodChange = diff.contains { if case .changed(let label, _, _) = $0 { return label == "Method" }; return false }
        XCTAssertTrue(hasMethodChange)
    }

    func testAddedHeader() {
        let req1 = makeRequest()
        let req2 = makeRequest(headers: [("Authorization", "Bearer token")])
        let diff = DiffTool.diff(req1: req1, req2: req2)
        let hasAdded = diff.contains { if case .added = $0 { return true }; return false }
        XCTAssertTrue(hasAdded)
    }

    func testRemovedHeader() {
        let req1 = makeRequest(headers: [("Authorization", "Bearer token")])
        let req2 = makeRequest()
        let diff = DiffTool.diff(req1: req1, req2: req2)
        let hasRemoved = diff.contains { if case .removed = $0 { return true }; return false }
        XCTAssertTrue(hasRemoved)
    }

    func testDifferentBody() {
        let req1 = makeRequest(body: "{\"old\":true}")
        let req2 = makeRequest(body: "{\"new\":true}")
        let diff = DiffTool.diff(req1: req1, req2: req2)
        let hasRemoved = diff.contains { if case .removed = $0 { return true }; return false }
        let hasAdded = diff.contains { if case .added = $0 { return true }; return false }
        XCTAssertTrue(hasRemoved)
        XCTAssertTrue(hasAdded)
    }

    func testDifferentStatus() {
        let req1 = makeRequest(statusCode: 200)
        let req2 = makeRequest(statusCode: 404)
        let diff = DiffTool.diff(req1: req1, req2: req2)
        let hasStatusChange = diff.contains { if case .changed(let label, _, _) = $0 { return label == "Status" }; return false }
        XCTAssertTrue(hasStatusChange)
    }
}

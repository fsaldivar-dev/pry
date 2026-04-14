import XCTest
@testable import PryLib

final class UnifiedMockTests: XCTestCase {

    func testMatchExactPath() {
        let mock = UnifiedMock(pattern: "/api/login", body: "{}")
        XCTAssertTrue(mock.matches(path: "/api/login", host: "example.com", method: "GET"))
        // Prefix match: longer path also matches
        XCTAssertTrue(mock.matches(path: "/api/login/callback", host: "example.com", method: "GET"))
        // Different path does not match
        XCTAssertFalse(mock.matches(path: "/api/logout", host: "example.com", method: "GET"))
    }

    func testMatchPrefix() {
        let mock = UnifiedMock(pattern: "/api/", body: "{}")
        XCTAssertTrue(mock.matches(path: "/api/users", host: "example.com", method: "GET"))
        XCTAssertTrue(mock.matches(path: "/api/posts/1", host: "example.com", method: "POST"))
        XCTAssertFalse(mock.matches(path: "/v2/api/users", host: "example.com", method: "GET"))
    }

    func testMatchGlob() {
        let mock = UnifiedMock(pattern: "/api/*/details", body: "{}")
        XCTAssertTrue(mock.matches(path: "/api/users/details", host: "example.com", method: "GET"))
        XCTAssertTrue(mock.matches(path: "/api/posts/details", host: "example.com", method: "GET"))
        XCTAssertFalse(mock.matches(path: "/api/users/list", host: "example.com", method: "GET"))
    }

    func testMatchMethod() {
        let postOnly = UnifiedMock(method: "POST", pattern: "/api/submit", body: "{}")
        XCTAssertTrue(postOnly.matches(path: "/api/submit", host: "example.com", method: "POST"))
        XCTAssertTrue(postOnly.matches(path: "/api/submit", host: "example.com", method: "post"))
        XCTAssertFalse(postOnly.matches(path: "/api/submit", host: "example.com", method: "GET"))

        // nil method matches all
        let anyMethod = UnifiedMock(pattern: "/api/submit", body: "{}")
        XCTAssertTrue(anyMethod.matches(path: "/api/submit", host: "example.com", method: "GET"))
        XCTAssertTrue(anyMethod.matches(path: "/api/submit", host: "example.com", method: "POST"))
        XCTAssertTrue(anyMethod.matches(path: "/api/submit", host: "example.com", method: "DELETE"))
    }

    func testMatchHost() {
        let mock = UnifiedMock(pattern: "/api/test", host: "example.com", body: "{}")
        XCTAssertTrue(mock.matches(path: "/api/test", host: "api.example.com", method: "GET"))
        XCTAssertTrue(mock.matches(path: "/api/test", host: "example.com", method: "GET"))
        XCTAssertFalse(mock.matches(path: "/api/test", host: "other.com", method: "GET"))

        // nil host matches all
        let anyHost = UnifiedMock(pattern: "/api/test", body: "{}")
        XCTAssertTrue(anyHost.matches(path: "/api/test", host: "any.host.com", method: "GET"))
    }

    func testDisabledMockDoesNotMatch() {
        var mock = UnifiedMock(pattern: "/api/test", body: "{}")
        mock.isEnabled = false
        XCTAssertFalse(mock.matches(path: "/api/test", host: "example.com", method: "GET"))
    }

    func testCodableRoundTrip() throws {
        let original = UnifiedMock(
            id: "test-123",
            method: "POST",
            pattern: "/api/users",
            host: "example.com",
            status: 201,
            headers: ["X-Custom": "value"],
            body: "{\"created\":true}",
            contentType: "application/json",
            delay: 500,
            notes: "Test mock",
            source: .scenario(project: "myproject", scenario: "happy-path"),
            isEnabled: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(UnifiedMock.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.id, "test-123")
        XCTAssertEqual(decoded.method, "POST")
        XCTAssertEqual(decoded.pattern, "/api/users")
        XCTAssertEqual(decoded.host, "example.com")
        XCTAssertEqual(decoded.status, 201)
        XCTAssertEqual(decoded.headers, ["X-Custom": "value"])
        XCTAssertEqual(decoded.body, "{\"created\":true}")
        XCTAssertEqual(decoded.contentType, "application/json")
        XCTAssertEqual(decoded.delay, 500)
        XCTAssertEqual(decoded.notes, "Test mock")
        XCTAssertEqual(decoded.source, .scenario(project: "myproject", scenario: "happy-path"))
        XCTAssertEqual(decoded.isEnabled, true)
    }

    func testMockSourceLabel() {
        XCTAssertEqual(MockSource.loose.label, "loose")
        XCTAssertEqual(MockSource.scenario(project: "p", scenario: "s1").label, "s1")
        XCTAssertEqual(MockSource.recording(name: "rec1").label, "rec1")
    }
}

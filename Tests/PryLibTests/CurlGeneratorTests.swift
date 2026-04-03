import XCTest
@testable import PryLib

final class CurlGeneratorTests: XCTestCase {
    func testSimpleGet() {
        let req = RequestStore.CapturedRequest(
            id: 1, timestamp: Date(), method: "GET", url: "/api/users",
            host: "api.example.com", appIcon: "🖥️", appName: "curl"
        )
        let curl = CurlGenerator.generate(from: req)
        XCTAssertTrue(curl.contains("curl"))
        XCTAssertTrue(curl.contains("http://api.example.com/api/users"))
    }

    func testWithHeaders() {
        var req = RequestStore.CapturedRequest(
            id: 1, timestamp: Date(), method: "GET", url: "/api/users",
            host: "api.example.com", appIcon: "🖥️", appName: "curl"
        )
        req.requestHeaders = [("Accept", "application/json"), ("Authorization", "Bearer token123")]
        let curl = CurlGenerator.generate(from: req)
        XCTAssertTrue(curl.contains("-H 'Accept: application/json'"))
        XCTAssertTrue(curl.contains("-H 'Authorization: Bearer token123'"))
    }

    func testPostWithBody() {
        var req = RequestStore.CapturedRequest(
            id: 1, timestamp: Date(), method: "POST", url: "/api/login",
            host: "api.example.com", appIcon: "🖥️", appName: "curl"
        )
        req.requestBody = "{\"email\":\"test@test.com\"}"
        let curl = CurlGenerator.generate(from: req)
        XCTAssertTrue(curl.contains("-X POST"))
        XCTAssertTrue(curl.contains("-d "))
        XCTAssertTrue(curl.contains("test@test.com"))
    }

    func testHTTPS() {
        var req = RequestStore.CapturedRequest(
            id: 1, timestamp: Date(), method: "GET", url: "/secure",
            host: "api.example.com", appIcon: "🖥️", appName: "curl"
        )
        req.statusCode = 200 // has response = was intercepted = HTTPS
        // URL starting with / on a watchlisted domain implies HTTPS
        let curl = CurlGenerator.generate(from: req, https: true)
        XCTAssertTrue(curl.contains("https://api.example.com/secure"))
    }
}

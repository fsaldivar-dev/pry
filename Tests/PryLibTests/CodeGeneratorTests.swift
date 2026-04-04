import XCTest
@testable import PryLib

final class CodeGeneratorTests: XCTestCase {
    private func makeRequest(method: String = "GET", url: String = "/api/users", host: String = "example.com", headers: [(String, String)] = [], body: String? = nil) -> RequestStore.CapturedRequest {
        RequestStore.CapturedRequest(method: method, url: url, host: host, appIcon: "🌐", appName: "test", requestHeaders: headers, requestBody: body)
    }

    func testSwiftGeneratorGET() {
        let req = makeRequest()
        let code = SwiftGenerator.generate(from: req, https: false)
        XCTAssertTrue(code.contains("URL(string:"))
        XCTAssertTrue(code.contains("URLRequest"))
        XCTAssertTrue(code.contains("http://example.com/api/users"))
    }

    func testSwiftGeneratorPOST() {
        let req = makeRequest(method: "POST", body: "{\"key\":\"value\"}")
        let code = SwiftGenerator.generate(from: req)
        XCTAssertTrue(code.contains("httpMethod = \"POST\""))
        XCTAssertTrue(code.contains("httpBody"))
    }

    func testSwiftGeneratorHeaders() {
        let req = makeRequest(headers: [("Authorization", "Bearer token")])
        let code = SwiftGenerator.generate(from: req)
        XCTAssertTrue(code.contains("setValue"))
        XCTAssertTrue(code.contains("Authorization"))
    }

    func testSwiftGeneratorHTTPS() {
        let req = makeRequest()
        let code = SwiftGenerator.generate(from: req, https: true)
        XCTAssertTrue(code.contains("https://"))
    }

    func testPythonGeneratorGET() {
        let req = makeRequest()
        let code = PythonGenerator.generate(from: req, https: false)
        XCTAssertTrue(code.contains("import requests"))
        XCTAssertTrue(code.contains("requests.get"))
    }

    func testPythonGeneratorPOST() {
        let req = makeRequest(method: "POST", body: "{\"key\":\"value\"}")
        let code = PythonGenerator.generate(from: req)
        XCTAssertTrue(code.contains("requests.post"))
    }

    func testPythonGeneratorHeaders() {
        let req = makeRequest(headers: [("Accept", "application/json")])
        let code = PythonGenerator.generate(from: req)
        XCTAssertTrue(code.contains("\"Accept\""))
    }
}

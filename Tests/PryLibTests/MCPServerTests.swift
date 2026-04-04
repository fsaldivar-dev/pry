import XCTest
@testable import PryLib

final class MCPServerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RequestStore.shared.clear()
    }

    override func tearDown() {
        RequestStore.shared.clear()
        super.tearDown()
    }

    func testListToolsResponse() throws {
        let request = "{\"jsonrpc\":\"2.0\",\"method\":\"tools/list\",\"id\":1}"
        let response = MCPServer.handleRequest(request)
        XCTAssertTrue(response.contains("tools"))
        XCTAssertTrue(response.contains("list_requests"))
        XCTAssertTrue(response.contains("search_requests"))
    }

    func testGetRequestsToolCall() throws {
        _ = RequestStore.shared.addRequest(method: "GET", url: "/api/users", host: "example.com", appIcon: "🌐", appName: "test", headers: [], body: nil)

        let request = "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"list_requests\",\"arguments\":{}},\"id\":2}"
        let response = MCPServer.handleRequest(request)
        XCTAssertTrue(response.contains("result"), "Response should contain result: \(response)")
        XCTAssertTrue(response.contains("content"), "Response should contain content: \(response)")
    }

    func testSearchToolCall() throws {
        _ = RequestStore.shared.addRequest(method: "GET", url: "/api/users", host: "example.com", appIcon: "🌐", appName: "test", headers: [], body: nil)

        let request = "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"search_requests\",\"arguments\":{\"query\":\"users\"}},\"id\":3}"
        let response = MCPServer.handleRequest(request)
        XCTAssertTrue(response.contains("result"), "Response should contain result: \(response)")
        XCTAssertTrue(response.contains("content"), "Response should contain content: \(response)")
    }

    func testExportCurlToolCall() throws {
        let id = RequestStore.shared.addRequest(method: "GET", url: "/api/users", host: "example.com", appIcon: "🌐", appName: "test", headers: [], body: nil)

        let request = "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"export_curl\",\"arguments\":{\"id\":\(id)}},\"id\":4}"
        let response = MCPServer.handleRequest(request)
        XCTAssertTrue(response.contains("curl"))
    }
}

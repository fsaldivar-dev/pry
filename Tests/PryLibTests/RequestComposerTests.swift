import XCTest
@testable import PryLib

final class RequestComposerTests: XCTestCase {
    func testBuildRequestGET() {
        let req = RequestComposer.buildRequest(method: "GET", urlString: "http://example.com/api", headers: [], body: nil)
        XCTAssertNotNil(req)
        XCTAssertEqual(req?.httpMethod, "GET")
        XCTAssertEqual(req?.url?.absoluteString, "http://example.com/api")
        XCTAssertNil(req?.httpBody)
    }

    func testBuildRequestPOST() {
        let req = RequestComposer.buildRequest(method: "POST", urlString: "http://example.com/api", headers: [], body: "{\"key\":\"value\"}")
        XCTAssertNotNil(req)
        XCTAssertEqual(req?.httpMethod, "POST")
        XCTAssertNotNil(req?.httpBody)
    }

    func testBuildRequestWithHeaders() {
        let req = RequestComposer.buildRequest(method: "GET", urlString: "http://example.com/api", headers: [("Authorization", "Bearer token"), ("Accept", "application/json")], body: nil)
        XCTAssertNotNil(req)
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testBuildRequestInvalidURL() {
        let req = RequestComposer.buildRequest(method: "GET", urlString: "", headers: [], body: nil)
        XCTAssertNil(req)
    }
}

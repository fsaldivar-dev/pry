import XCTest
@testable import PryLib

final class ReverseProxyTests: XCTestCase {
    func testParseTargetOriginHTTPS() {
        let result = ReverseProxyHandler.parseTargetOrigin("https://api.myapp.com")
        XCTAssertEqual(result.host, "api.myapp.com")
        XCTAssertEqual(result.port, 443)
        XCTAssertTrue(result.isHTTPS)
    }

    func testParseTargetOriginHTTP() {
        let result = ReverseProxyHandler.parseTargetOrigin("http://api.myapp.com")
        XCTAssertEqual(result.host, "api.myapp.com")
        XCTAssertEqual(result.port, 80)
        XCTAssertFalse(result.isHTTPS)
    }

    func testParseTargetOriginWithPort() {
        let result = ReverseProxyHandler.parseTargetOrigin("https://api.myapp.com:8443")
        XCTAssertEqual(result.host, "api.myapp.com")
        XCTAssertEqual(result.port, 8443)
        XCTAssertTrue(result.isHTTPS)
    }

    func testParseTargetOriginBareHost() {
        let result = ReverseProxyHandler.parseTargetOrigin("api.myapp.com")
        XCTAssertEqual(result.host, "api.myapp.com")
        XCTAssertEqual(result.port, 443)
        XCTAssertTrue(result.isHTTPS)
    }
}

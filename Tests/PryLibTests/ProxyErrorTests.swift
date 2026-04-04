import XCTest
@testable import PryLib

final class ProxyErrorTests: XCTestCase {
    func testAlreadyRunningDescription() {
        let err = ProxyError.alreadyRunning
        XCTAssertEqual(err.description, "Proxy is already running")
    }

    func testNotRunningDescription() {
        let err = ProxyError.notRunning
        XCTAssertEqual(err.description, "Proxy is not running")
    }

    func testInvalidPortDescription() {
        let err = ProxyError.invalidPort("abc")
        XCTAssertTrue(err.description.contains("abc"))
    }

    func testMockFileNotFoundDescription() {
        let err = ProxyError.mockFileNotFound("/tmp/nope.json")
        XCTAssertTrue(err.description.contains("/tmp/nope.json"))
    }

    func testInvalidJSONDescription() {
        let err = ProxyError.invalidJSON("unexpected token")
        XCTAssertTrue(err.description.contains("unexpected token"))
    }

    func testConnectionFailedDescription() {
        let err = ProxyError.connectionFailed("example.com")
        XCTAssertTrue(err.description.contains("example.com"))
    }

    func testConformsToError() {
        let err: Error = ProxyError.alreadyRunning
        XCTAssertFalse(err.localizedDescription.isEmpty)
    }
}

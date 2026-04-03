import XCTest
@testable import PryLib

final class ConfigTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Config.clearMocks()
        Config.clearLog()
    }

    override func tearDown() {
        Config.clearMocks()
        Config.clearLog()
        super.tearDown()
    }

    func testDefaultPort() {
        XCTAssertEqual(Config.defaultPort, 8080)
    }

    func testMockStorage() {
        Config.saveMock(path: "/api/test", response: "{\"ok\":true}")
        let mocks = Config.loadMocks()
        XCTAssertEqual(mocks["/api/test"], "{\"ok\":true}")
    }

    func testMockClear() {
        Config.saveMock(path: "/api/test", response: "{}")
        Config.clearMocks()
        XCTAssertTrue(Config.loadMocks().isEmpty)
    }

    func testDomainScopedMock() {
        Config.saveMock(path: "api.com:/users", response: "{\"users\":[]}")
        let mocks = Config.loadMocks()
        XCTAssertEqual(mocks["api.com:/users"], "{\"users\":[]}")
    }

    func testLogAppendAndRead() {
        Config.appendLog("test entry 1")
        Config.appendLog("test entry 2")
        let entries = Config.readLog()
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[0].contains("test entry 1"))
        XCTAssertTrue(entries[1].contains("test entry 2"))
    }

    func testLogClear() {
        Config.appendLog("something")
        Config.clearLog()
        XCTAssertTrue(Config.readLog().isEmpty)
    }
}

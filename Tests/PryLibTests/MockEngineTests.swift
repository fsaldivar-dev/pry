import XCTest
@testable import PryLib

final class MockEngineTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockEngine.shared.clearAll()
    }

    override func tearDown() {
        MockEngine.shared.clearAll()
        super.tearDown()
    }

    func testAddAndFindLooseMock() {
        let mock = UnifiedMock(pattern: "/api/users", status: 200, body: "{\"users\":[]}")
        MockEngine.shared.addLooseMock(mock)

        let found = MockEngine.shared.findMock(path: "/api/users", host: "example.com", method: "GET")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.body, "{\"users\":[]}")
        XCTAssertEqual(found?.status, 200)
    }

    func testLoosePriorityOverScenario() {
        let scenarioMock = UnifiedMock(pattern: "/api/data", status: 200, body: "{\"from\":\"scenario\"}", source: .scenario(project: "p", scenario: "s"))
        let looseMock = UnifiedMock(pattern: "/api/data", status: 500, body: "{\"from\":\"loose\"}", source: .loose)

        MockEngine.shared.loadScenarioMocks([scenarioMock])
        MockEngine.shared.addLooseMock(looseMock)

        let found = MockEngine.shared.findMock(path: "/api/data", host: "example.com", method: "GET")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.status, 500)
        XCTAssertEqual(found?.body, "{\"from\":\"loose\"}")
    }

    func testScenarioMocks() {
        let mock1 = UnifiedMock(pattern: "/api/a", status: 200, body: "{\"a\":true}")
        let mock2 = UnifiedMock(pattern: "/api/b", status: 404, body: "{\"error\":\"not found\"}")
        MockEngine.shared.loadScenarioMocks([mock1, mock2])

        XCTAssertNotNil(MockEngine.shared.findMock(path: "/api/a", host: "x.com", method: "GET"))
        let found = MockEngine.shared.findMock(path: "/api/b", host: "x.com", method: "GET")
        XCTAssertEqual(found?.status, 404)
    }

    func testClearAll() {
        MockEngine.shared.addLooseMock(UnifiedMock(pattern: "/a", body: "{}"))
        MockEngine.shared.loadScenarioMocks([UnifiedMock(pattern: "/b", body: "{}")])
        XCTAssertEqual(MockEngine.shared.count, 2)

        MockEngine.shared.clearAll()
        XCTAssertEqual(MockEngine.shared.count, 0)
        XCTAssertNil(MockEngine.shared.findMock(path: "/a", host: "x.com", method: "GET"))
        XCTAssertNil(MockEngine.shared.findMock(path: "/b", host: "x.com", method: "GET"))
    }

    func testRemoveLooseMock() {
        let mock = UnifiedMock(id: "remove-me", pattern: "/api/test", body: "{}")
        MockEngine.shared.addLooseMock(mock)
        XCTAssertEqual(MockEngine.shared.count, 1)

        MockEngine.shared.removeLooseMock(id: "remove-me")
        XCTAssertEqual(MockEngine.shared.count, 0)
        XCTAssertNil(MockEngine.shared.findMock(path: "/api/test", host: "x.com", method: "GET"))
    }

    func testMethodFiltering() {
        let postMock = UnifiedMock(method: "POST", pattern: "/api/submit", status: 201, body: "{\"ok\":true}")
        MockEngine.shared.addLooseMock(postMock)

        XCTAssertNotNil(MockEngine.shared.findMock(path: "/api/submit", host: "x.com", method: "POST"))
        XCTAssertNil(MockEngine.shared.findMock(path: "/api/submit", host: "x.com", method: "GET"))
        XCTAssertNil(MockEngine.shared.findMock(path: "/api/submit", host: "x.com", method: "DELETE"))
    }

    func testCount() {
        XCTAssertEqual(MockEngine.shared.count, 0)

        MockEngine.shared.addLooseMock(UnifiedMock(pattern: "/a", body: "{}"))
        XCTAssertEqual(MockEngine.shared.count, 1)

        MockEngine.shared.loadScenarioMocks([
            UnifiedMock(pattern: "/b", body: "{}"),
            UnifiedMock(pattern: "/c", body: "{}")
        ])
        XCTAssertEqual(MockEngine.shared.count, 3)

        MockEngine.shared.clearLooseMocks()
        XCTAssertEqual(MockEngine.shared.count, 2)

        MockEngine.shared.clearScenarioMocks()
        XCTAssertEqual(MockEngine.shared.count, 0)
    }
}

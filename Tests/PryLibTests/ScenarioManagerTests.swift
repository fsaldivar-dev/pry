import XCTest
@testable import PryLib

final class ScenarioManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Clean up any leftover test scenarios
        for name in ScenarioManager.list() {
            ScenarioManager.delete(name: name)
        }
        ScenarioManager.deactivate()
    }

    override func tearDown() {
        for name in ScenarioManager.list() {
            ScenarioManager.delete(name: name)
        }
        ScenarioManager.deactivate()
        super.tearDown()
    }

    func testCreateAndLoad() throws {
        try ScenarioManager.create(name: "test-scenario")
        let loaded = ScenarioManager.load(name: "test-scenario")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "test-scenario")
        XCTAssertTrue(loaded?.watchlist.isEmpty ?? false)
        XCTAssertTrue(loaded?.mocks.isEmpty ?? false)
    }

    func testList() throws {
        try ScenarioManager.create(name: "alpha")
        try ScenarioManager.create(name: "beta")
        let names = ScenarioManager.list()
        XCTAssertEqual(names, ["alpha", "beta"])
    }

    func testDelete() throws {
        try ScenarioManager.create(name: "to-delete")
        XCTAssertNotNil(ScenarioManager.load(name: "to-delete"))
        ScenarioManager.delete(name: "to-delete")
        XCTAssertNil(ScenarioManager.load(name: "to-delete"))
    }

    func testSaveWithData() throws {
        var scenario = Scenario(name: "with-data")
        scenario.watchlist = ["api.example.com"]
        scenario.mocks = [UnifiedMock(pattern: "/api/test", status: 200, body: "{\"ok\":true}")]
        scenario.breakpoints = ["/api/login"]
        try ScenarioManager.save(scenario)

        let loaded = ScenarioManager.load(name: "with-data")
        XCTAssertEqual(loaded?.watchlist, ["api.example.com"])
        XCTAssertEqual(loaded?.mocks.count, 1)
        XCTAssertEqual(loaded?.mocks.first?.pattern, "/api/test")
        XCTAssertEqual(loaded?.breakpoints, ["/api/login"])
    }

    func testActivateAndDeactivate() throws {
        var scenario = Scenario(name: "active-test")
        scenario.watchlist = ["test.example.com"]
        scenario.mocks = [UnifiedMock(pattern: "/test", status: 200, body: "{}")]
        scenario.blocklist = ["blocked.com"]
        try ScenarioManager.save(scenario)

        let result = ScenarioManager.activate(name: "active-test")
        XCTAssertTrue(result)
        XCTAssertEqual(ScenarioManager.active(), "active-test")

        // Verify config was applied
        XCTAssertTrue(Watchlist.load().contains("test.example.com"))
        let mocks = MockEngine.shared.activeMocks()
        XCTAssertTrue(mocks.contains(where: { $0.pattern == "/test" }))
        XCTAssertTrue(BlockList.isBlocked("blocked.com"))

        // Deactivate
        ScenarioManager.deactivate()
        XCTAssertNil(ScenarioManager.active())

        // Verify config was cleared
        XCTAssertFalse(Watchlist.load().contains("test.example.com"))
        XCTAssertTrue(MockEngine.shared.activeMocks().isEmpty)
        XCTAssertFalse(BlockList.isBlocked("blocked.com"))
    }

    func testActivateNonexistent() {
        let result = ScenarioManager.activate(name: "nonexistent")
        XCTAssertFalse(result)
    }

    func testActiveReturnsNilWhenNone() {
        XCTAssertNil(ScenarioManager.active())
    }
}

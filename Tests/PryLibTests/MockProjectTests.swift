import XCTest
@testable import PryLib

final class MockProjectTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockProject.clear()
        MockEngine.shared.clearAll()
        Config.clearMocks()
    }

    override func tearDown() {
        MockProject.clear()
        MockEngine.shared.clearAll()
        Config.clearMocks()
        super.tearDown()
    }

    func testInitProject() throws {
        try MockProject.initProject()
        XCTAssertTrue(FileManager.default.fileExists(atPath: StoragePaths.mockingDir))
    }

    func testSaveAndLoad() throws {
        let mock = ProjectMock(pattern: "/api/users", body: "{\"users\":[]}")
        try MockProject.save(mock)
        let loaded = MockProject.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].pattern, "/api/users")
        XCTAssertEqual(loaded[0].body, "{\"users\":[]}")
        XCTAssertEqual(loaded[0].status, 200)
    }

    func testSaveWithAllFields() throws {
        let mock = ProjectMock(pattern: "/api/login", body: "{\"token\":\"abc\"}", method: "POST",
                               status: 201, headers: ["X-Custom": "test"], delay: 500, notes: "Login mock")
        try MockProject.save(mock)
        let loaded = MockProject.loadAll()
        XCTAssertEqual(loaded[0].method, "POST")
        XCTAssertEqual(loaded[0].status, 201)
        XCTAssertEqual(loaded[0].delay, 500)
        XCTAssertEqual(loaded[0].notes, "Login mock")
    }

    func testRemove() throws {
        try MockProject.save(ProjectMock(pattern: "/api/a", body: "{}"))
        try MockProject.save(ProjectMock(pattern: "/api/b", body: "{}"))
        MockProject.remove(pattern: "/api/a")
        XCTAssertEqual(MockProject.loadAll().count, 1)
        XCTAssertEqual(MockProject.loadAll()[0].pattern, "/api/b")
    }

    func testClear() throws {
        try MockProject.save(ProjectMock(pattern: "/api/test", body: "{}"))
        MockProject.clear()
        XCTAssertTrue(MockProject.loadAll().isEmpty)
    }

    func testApplyAll() throws {
        try MockProject.save(ProjectMock(pattern: "/api/users", body: "{\"users\":[]}"))
        try MockProject.save(ProjectMock(pattern: "/api/login", body: "{\"token\":\"x\"}"))
        MockProject.applyAll()
        let mocks = MockEngine.shared.looseMockList()
        XCTAssertEqual(mocks.count, 2)
        XCTAssertTrue(mocks.contains(where: { $0.pattern == "/api/users" }))
        XCTAssertTrue(mocks.contains(where: { $0.pattern == "/api/login" }))
    }

    func testCount() throws {
        XCTAssertEqual(MockProject.count(), 0)
        try MockProject.save(ProjectMock(pattern: "/api/a", body: "{}"))
        try MockProject.save(ProjectMock(pattern: "/api/b", body: "{}"))
        XCTAssertEqual(MockProject.count(), 2)
    }

    func testIDGeneration() {
        let mock = ProjectMock(pattern: "/api/users/me", body: "{}")
        XCTAssertEqual(mock.id, "api-users-me")
    }
}

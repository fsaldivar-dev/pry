import XCTest
@testable import PryLib

final class SessionManagerTests: XCTestCase {
    private let testPath = "/tmp/pry-test-session.json"

    override func setUp() {
        super.setUp()
        RequestStore.shared.clear()
        try? FileManager.default.removeItem(atPath: testPath)
    }

    override func tearDown() {
        RequestStore.shared.clear()
        try? FileManager.default.removeItem(atPath: testPath)
        super.tearDown()
    }

    func testSaveAndLoad() throws {
        // Add some requests
        let id1 = RequestStore.shared.addRequest(method: "GET", url: "/api/users", host: "example.com", appIcon: "🌐", appName: "test", headers: [("Accept", "application/json")], body: nil)
        RequestStore.shared.updateResponse(id: id1, statusCode: 200, headers: [], body: "{\"users\":[]}")

        let _ = RequestStore.shared.addRequest(method: "POST", url: "/api/login", host: "example.com", appIcon: "🌐", appName: "test", headers: [], body: "{\"user\":\"admin\"}")

        // Save
        try SessionManager.save(to: testPath)

        // Clear and reload
        RequestStore.shared.clear()
        XCTAssertEqual(RequestStore.shared.count(), 0)

        try SessionManager.load(from: testPath)
        XCTAssertEqual(RequestStore.shared.count(), 2)

        let all = RequestStore.shared.getAll()
        XCTAssertEqual(all[0].method, "GET")
        XCTAssertEqual(all[0].url, "/api/users")
        XCTAssertEqual(all[1].method, "POST")
    }

    func testSaveEmptySession() throws {
        try SessionManager.save(to: testPath)
        RequestStore.shared.clear()
        try SessionManager.load(from: testPath)
        XCTAssertEqual(RequestStore.shared.count(), 0)
    }

    func testLoadNonExistentFile() {
        XCTAssertThrowsError(try SessionManager.load(from: "/tmp/nonexistent-pry-session.json"))
    }
}

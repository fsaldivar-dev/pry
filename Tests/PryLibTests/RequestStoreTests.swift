import XCTest
@testable import PryLib

final class RequestStoreTests: XCTestCase {
    var store: RequestStore!

    override func setUp() {
        super.setUp()
        store = RequestStore()
    }

    func testAddRequest() {
        let id = store.addRequest(method: "GET", url: "/api/users", host: "example.com", appIcon: "🖥️", appName: "curl", headers: [], body: nil)
        XCTAssertEqual(id, 1)
        XCTAssertEqual(store.count(), 1)
    }

    func testUpdateResponse() {
        let id = store.addRequest(method: "GET", url: "/api/users", host: "example.com", appIcon: "🖥️", appName: "curl", headers: [], body: nil)
        store.updateResponse(id: id, statusCode: 200, headers: [("Content-Type", "application/json")], body: "{\"users\":[]}")
        let req = store.get(id: id)
        XCTAssertEqual(req?.statusCode, 200)
        XCTAssertEqual(req?.responseBody, "{\"users\":[]}")
    }

    func testAddTunnel() {
        store.addTunnel(host: "google.com")
        let all = store.getAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(all[0].isTunnel)
    }

    func testClear() {
        store.addRequest(method: "GET", url: "/", host: "a.com", appIcon: "", appName: "", headers: [], body: nil)
        store.addRequest(method: "POST", url: "/", host: "b.com", appIcon: "", appName: "", headers: [], body: nil)
        store.clear()
        XCTAssertEqual(store.count(), 0)
    }

    // MARK: - Filter tests (RED — methods don't exist yet)

    func testFilterByMethod() {
        store.addRequest(method: "GET", url: "/a", host: "a.com", appIcon: "", appName: "", headers: [], body: nil)
        store.addRequest(method: "POST", url: "/b", host: "b.com", appIcon: "", appName: "", headers: [], body: nil)
        store.addRequest(method: "GET", url: "/c", host: "c.com", appIcon: "", appName: "", headers: [], body: nil)
        let filtered = store.filter(method: "GET")
        XCTAssertEqual(filtered.count, 2)
    }

    func testFilterByStatusCode() {
        let id1 = store.addRequest(method: "GET", url: "/ok", host: "a.com", appIcon: "", appName: "", headers: [], body: nil)
        let id2 = store.addRequest(method: "GET", url: "/err", host: "b.com", appIcon: "", appName: "", headers: [], body: nil)
        store.updateResponse(id: id1, statusCode: 200, headers: [], body: nil)
        store.updateResponse(id: id2, statusCode: 404, headers: [], body: nil)
        let errors = store.filter(statusRange: 400...599)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].url, "/err")
    }

    func testSearchByText() {
        store.addRequest(method: "GET", url: "/api/users", host: "example.com", appIcon: "", appName: "", headers: [], body: nil)
        store.addRequest(method: "POST", url: "/api/login", host: "example.com", appIcon: "", appName: "", headers: [], body: nil)
        let results = store.search("login")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].url.contains("login"))
    }
}

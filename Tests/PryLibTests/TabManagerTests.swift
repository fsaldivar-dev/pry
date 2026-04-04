import XCTest
@testable import PryLib

final class TabManagerTests: XCTestCase {
    func testDefaultTabExists() {
        let tm = TabManager()
        XCTAssertEqual(tm.tabs.count, 1)
        XCTAssertEqual(tm.tabs[0].name, "All")
        XCTAssertNil(tm.tabs[0].filter)
    }

    func testAddTab() {
        let tm = TabManager()
        tm.addTab(name: "API", filter: "api.myapp.com")
        XCTAssertEqual(tm.tabs.count, 2)
        XCTAssertEqual(tm.tabs[1].name, "API")
        XCTAssertEqual(tm.tabs[1].filter, "api.myapp.com")
    }

    func testFilteredRequestsAllTab() {
        let store = RequestStore()
        _ = store.addRequest(method: "GET", url: "/api", host: "example.com", appIcon: "🌐", appName: "test", headers: [], body: nil)
        _ = store.addRequest(method: "POST", url: "/login", host: "other.com", appIcon: "🌐", appName: "test", headers: [], body: nil)

        let tm = TabManager()
        let filtered = tm.filteredRequests(from: store)
        XCTAssertEqual(filtered.count, 2)
    }

    func testFilteredRequestsWithFilter() {
        let store = RequestStore()
        _ = store.addRequest(method: "GET", url: "/api", host: "example.com", appIcon: "🌐", appName: "test", headers: [], body: nil)
        _ = store.addRequest(method: "POST", url: "/login", host: "other.com", appIcon: "🌐", appName: "test", headers: [], body: nil)

        let tm = TabManager()
        tm.addTab(name: "Example", filter: "example.com")
        tm.activeTabIndex = 1
        let filtered = tm.filteredRequests(from: store)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].host, "example.com")
    }
}

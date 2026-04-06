import XCTest
@testable import PryLib
@testable import PryKit

@available(macOS 14, *)
final class RequestStoreWrapperTests: XCTestCase {

    @MainActor
    func testUpdatesOnChange() async throws {
        let store = RequestStore()
        let wrapper = RequestStoreWrapper(store: store)

        _ = store.addRequest(method: "GET", url: "/test", host: "example.com",
                             appIcon: "🌐", appName: "test", headers: [], body: nil)

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(wrapper.requests.count, 1)
    }

    @MainActor
    func testFilteredRequestsByMethod() async throws {
        let store = RequestStore()
        let wrapper = RequestStoreWrapper(store: store)

        _ = store.addRequest(method: "GET", url: "/a", host: "h", appIcon: "", appName: "", headers: [], body: nil)
        _ = store.addRequest(method: "POST", url: "/b", host: "h", appIcon: "", appName: "", headers: [], body: nil)
        _ = store.addRequest(method: "GET", url: "/c", host: "h", appIcon: "", appName: "", headers: [], body: nil)

        try await Task.sleep(for: .milliseconds(100))
        wrapper.filterMethod = "POST"
        XCTAssertEqual(wrapper.filteredRequests.count, 1)
    }

    @MainActor
    func testFilteredRequestsBySearch() async throws {
        let store = RequestStore()
        let wrapper = RequestStoreWrapper(store: store)

        _ = store.addRequest(method: "GET", url: "/api/users", host: "api.com", appIcon: "", appName: "", headers: [], body: nil)
        _ = store.addRequest(method: "GET", url: "/other", host: "other.com", appIcon: "", appName: "", headers: [], body: nil)

        try await Task.sleep(for: .milliseconds(100))
        wrapper.filterText = "users"
        XCTAssertEqual(wrapper.filteredRequests.count, 1)
    }

    @MainActor
    func testFilteredRequestsCombined() async throws {
        let store = RequestStore()
        let wrapper = RequestStoreWrapper(store: store)

        _ = store.addRequest(method: "GET", url: "/api/users", host: "api.com", appIcon: "", appName: "", headers: [], body: nil)
        store.updateResponse(id: 1, statusCode: 200, headers: [], body: nil)
        _ = store.addRequest(method: "POST", url: "/api/users", host: "api.com", appIcon: "", appName: "", headers: [], body: nil)
        store.updateResponse(id: 2, statusCode: 201, headers: [], body: nil)
        _ = store.addRequest(method: "GET", url: "/api/items", host: "api.com", appIcon: "", appName: "", headers: [], body: nil)
        store.updateResponse(id: 3, statusCode: 404, headers: [], body: nil)

        try await Task.sleep(for: .milliseconds(100))
        wrapper.filterMethod = "GET"
        wrapper.filterText = "users"
        let results = wrapper.filteredRequests
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.url, "/api/users")
    }
}

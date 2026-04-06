import Testing
@testable import PryLib
@testable import PryKit

@Suite("RequestStoreWrapper")
struct RequestStoreWrapperTests {

    @available(macOS 14, *)
    @Test func updatesOnChange() async throws {
        let store = RequestStore()
        let wrapper = await RequestStoreWrapper(store: store)

        _ = store.addRequest(method: "GET", url: "/test", host: "example.com",
                             appIcon: "🌐", appName: "test", headers: [], body: nil)

        // Wait for MainActor dispatch
        try await Task.sleep(for: .milliseconds(100))
        #expect(await wrapper.requests.count == 1)
    }

    @available(macOS 14, *)
    @Test func filteredRequestsByMethod() async throws {
        let store = RequestStore()
        let wrapper = await RequestStoreWrapper(store: store)

        _ = store.addRequest(method: "GET", url: "/a", host: "h", appIcon: "", appName: "", headers: [], body: nil)
        _ = store.addRequest(method: "POST", url: "/b", host: "h", appIcon: "", appName: "", headers: [], body: nil)
        _ = store.addRequest(method: "GET", url: "/c", host: "h", appIcon: "", appName: "", headers: [], body: nil)

        try await Task.sleep(for: .milliseconds(100))
        await MainActor.run { wrapper.filterMethod = "POST" }
        #expect(await wrapper.filteredRequests.count == 1)
    }

    @available(macOS 14, *)
    @Test func filteredRequestsBySearch() async throws {
        let store = RequestStore()
        let wrapper = await RequestStoreWrapper(store: store)

        _ = store.addRequest(method: "GET", url: "/api/users", host: "api.com", appIcon: "", appName: "", headers: [], body: nil)
        _ = store.addRequest(method: "GET", url: "/other", host: "other.com", appIcon: "", appName: "", headers: [], body: nil)

        try await Task.sleep(for: .milliseconds(100))
        await MainActor.run { wrapper.filterText = "users" }
        #expect(await wrapper.filteredRequests.count == 1)
    }

    @available(macOS 14, *)
    @Test func filteredRequestsCombined() async throws {
        let store = RequestStore()
        let wrapper = await RequestStoreWrapper(store: store)

        _ = store.addRequest(method: "GET", url: "/api/users", host: "api.com", appIcon: "", appName: "", headers: [], body: nil)
        store.updateResponse(id: 1, statusCode: 200, headers: [], body: nil)
        _ = store.addRequest(method: "POST", url: "/api/users", host: "api.com", appIcon: "", appName: "", headers: [], body: nil)
        store.updateResponse(id: 2, statusCode: 201, headers: [], body: nil)
        _ = store.addRequest(method: "GET", url: "/api/items", host: "api.com", appIcon: "", appName: "", headers: [], body: nil)
        store.updateResponse(id: 3, statusCode: 404, headers: [], body: nil)

        try await Task.sleep(for: .milliseconds(100))
        await MainActor.run {
            wrapper.filterMethod = "GET"
            wrapper.filterText = "users"
        }
        let results = await wrapper.filteredRequests
        #expect(results.count == 1)
        #expect(results.first?.url == "/api/users")
    }
}

import XCTest
@testable import PryApp
import PryLib

@available(macOS 14, *)
final class SessionPersistenceStoreTests: XCTestCase {
    var bus: EventBus!
    var store: SessionPersistenceStore!
    var tempPath: String!

    @MainActor
    override func setUp() async throws {
        let dir = NSTemporaryDirectory() + "pry-session-store-tests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        tempPath = dir + "/session.jsonl"
        SessionPersistence.overridePath = tempPath
        // Force disabled por default en cada test.
        SessionPersistence.setEnabled(false)
        bus = EventBus()
        store = SessionPersistenceStore(bus: bus)
    }

    override func tearDown() async throws {
        SessionPersistence.overridePath = nil
        let dir = (tempPath as NSString).deletingLastPathComponent
        try? FileManager.default.removeItem(atPath: dir)
    }

    @MainActor
    func test_initial_isEnabled_false() {
        XCTAssertFalse(store.isEnabled)
    }

    @MainActor
    func test_toggle_persists_to_userDefaults() {
        store.isEnabled = true
        XCTAssertTrue(SessionPersistence.isEnabled())
        store.isEnabled = false
        XCTAssertFalse(SessionPersistence.isEnabled())
    }

    @MainActor
    func test_ignoresEvents_when_disabled() async throws {
        store.isEnabled = false
        await bus.publish(RequestCapturedEvent(
            requestID: 1, method: "GET", host: "example.com",
            url: "/api", headers: [], body: nil
        ))
        await bus.publish(ResponseReceivedEvent(
            requestID: 1, status: 200, headers: [],
            body: nil, latencyMs: 10, isMock: false
        ))
        try await Task.sleep(nanoseconds: 200_000_000)
        store.refreshStats()
        XCTAssertEqual(store.persistedCount, 0)
    }

    @MainActor
    func test_persistsRequest_when_enabled() async throws {
        store.isEnabled = true
        await bus.publish(RequestCapturedEvent(
            requestID: 1, method: "POST", host: "api.example.com",
            url: "/users", headers: [("Authorization", "Bearer x")],
            body: #"{"name":"test"}"#
        ))
        await bus.publish(ResponseReceivedEvent(
            requestID: 1, status: 201,
            headers: [("Content-Type", "application/json")],
            body: #"{"id":42}"#, latencyMs: 123, isMock: false
        ))
        await waitUntil { SessionPersistence.currentCount() >= 1 }
        store.refreshStats()

        XCTAssertEqual(store.persistedCount, 1)
        let loaded = SessionPersistence.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].method, "POST")
        XCTAssertEqual(loaded[0].url, "/users")
        XCTAssertEqual(loaded[0].statusCode, 201)
        XCTAssertEqual(loaded[0].latencyMs, 123)
    }

    @MainActor
    func test_incomplete_requests_discarded_when_disabled_mid_flight() async throws {
        store.isEnabled = true
        await bus.publish(RequestCapturedEvent(
            requestID: 1, method: "GET", host: "example.com",
            url: "/", headers: [], body: nil
        ))
        try await Task.sleep(nanoseconds: 100_000_000)

        // Disable antes del response.
        store.isEnabled = false

        await bus.publish(ResponseReceivedEvent(
            requestID: 1, status: 200, headers: [],
            body: nil, latencyMs: 10, isMock: false
        ))
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(SessionPersistence.currentCount(), 0)
    }

    @MainActor
    func test_clearPersisted_removesFile() async throws {
        store.isEnabled = true
        await bus.publish(RequestCapturedEvent(
            requestID: 1, method: "GET", host: "e.com",
            url: "/", headers: [], body: nil
        ))
        await bus.publish(ResponseReceivedEvent(
            requestID: 1, status: 200, headers: [],
            body: nil, latencyMs: 0, isMock: false
        ))
        await waitUntil { SessionPersistence.currentCount() >= 1 }
        store.refreshStats()
        XCTAssertGreaterThan(store.persistedCount, 0)

        store.clearPersisted()
        XCTAssertEqual(store.persistedCount, 0)
    }

    // MARK: - Helpers

    /// Poll con timeout hasta que una condición sea true. Reemplaza sleeps fijos
    /// que son flaky en CI con load alta.
    @MainActor
    fileprivate func waitUntil(timeout: TimeInterval = 3.0, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

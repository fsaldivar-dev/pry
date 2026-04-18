import XCTest
@testable import PryApp
import PryLib

@available(macOS 14, *)
final class RecordingsStoreTests: XCTestCase {
    var bus: EventBus!
    var store: RecordingsStore!

    @MainActor
    override func setUp() async throws {
        bus = EventBus()
        store = RecordingsStore(bus: bus)
    }

    @MainActor
    override func tearDown() async throws {
        _ = store.stop()
    }

    // MARK: - Lifecycle

    @MainActor
    func test_initialState_notRecording() {
        XCTAssertFalse(store.isRecording)
        XCTAssertNil(store.currentRecordingName)
        XCTAssertEqual(store.currentStepCount, 0)
    }

    @MainActor
    func test_start_togglesIsRecording() {
        store.start(name: "test-\(UUID().uuidString)")
        XCTAssertTrue(store.isRecording)
    }

    @MainActor
    func test_start_trimsWhitespace() {
        store.start(name: "  named  ")
        XCTAssertEqual(store.currentRecordingName, "named")
    }

    @MainActor
    func test_start_ignoresEmpty() {
        store.start(name: "   ")
        XCTAssertFalse(store.isRecording)
    }

    @MainActor
    func test_stop_clearsState() {
        store.start(name: "test-\(UUID().uuidString)")
        _ = store.stop()
        XCTAssertFalse(store.isRecording)
        XCTAssertNil(store.currentRecordingName)
        XCTAssertEqual(store.currentStepCount, 0)
    }

    @MainActor
    func test_stop_withoutStart_returnsNil() {
        XCTAssertNil(store.stop())
    }

    // MARK: - Event subscription

    @MainActor
    func test_capturesRequestEvents_whenRecording() async throws {
        let name = "test-\(UUID().uuidString)"
        store.start(name: name)

        let reqEvent = RequestCapturedEvent(
            requestID: 1, method: "GET", host: "example.com",
            url: "/api/users", headers: [("Accept", "*/*")], body: nil
        )
        await bus.publish(reqEvent)

        let respEvent = ResponseReceivedEvent(
            requestID: 1, status: 200,
            headers: [("Content-Type", "application/json")],
            body: #"{"ok":true}"#, latencyMs: 42, isMock: false
        )
        await bus.publish(respEvent)
        await waitUntil { self.store.currentStepCount == 1 }

        XCTAssertEqual(store.currentStepCount, 1)
    }

    @MainActor
    func test_ignoresEvents_whenNotRecording() async throws {
        // No start() — sólo publish events.
        let reqEvent = RequestCapturedEvent(
            requestID: 1, method: "GET", host: "example.com",
            url: "/", headers: [], body: nil
        )
        await bus.publish(reqEvent)
        // Dar tiempo a que el subscribe loop corra — pero no esperar un cambio
        // que nunca va a venir (isRecording=false nunca incrementa step count).
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(store.currentStepCount, 0)
    }

    @MainActor
    func test_filterDomains_rejectsUnmatchedHost() async throws {
        store.start(name: "test-\(UUID().uuidString)", domains: ["allowed.com"])

        let req1 = RequestCapturedEvent(requestID: 1, method: "GET",
            host: "other.com", url: "/", headers: [], body: nil)
        let req2 = RequestCapturedEvent(requestID: 2, method: "GET",
            host: "allowed.com", url: "/", headers: [], body: nil)
        await bus.publish(req1)
        await bus.publish(req2)

        let resp1 = ResponseReceivedEvent(requestID: 1, status: 200, headers: [],
            body: nil, latencyMs: 0, isMock: false)
        let resp2 = ResponseReceivedEvent(requestID: 2, status: 200, headers: [],
            body: nil, latencyMs: 0, isMock: false)
        await bus.publish(resp1)
        await bus.publish(resp2)
        await waitUntil { self.store.currentStepCount == 1 }

        // Sólo req2 debería haber generado un step (host allowed.com matchea el filtro).
        XCTAssertEqual(store.currentStepCount, 1)
    }

    @MainActor
    func test_filterDomains_matchesSubdomain() async throws {
        store.start(name: "test-\(UUID().uuidString)", domains: ["example.com"])

        let req = RequestCapturedEvent(requestID: 1, method: "GET",
            host: "api.example.com", url: "/", headers: [], body: nil)
        await bus.publish(req)
        let resp = ResponseReceivedEvent(requestID: 1, status: 200, headers: [],
            body: nil, latencyMs: 0, isMock: false)
        await bus.publish(resp)
        await waitUntil { self.store.currentStepCount == 1 }

        XCTAssertEqual(store.currentStepCount, 1)
    }

    // MARK: - Persistence

    @MainActor
    func test_stop_persistsRecordingToDisk() async throws {
        let name = "test-persist-\(UUID().uuidString)"
        store.start(name: name)

        let req = RequestCapturedEvent(requestID: 1, method: "GET",
            host: "example.com", url: "/api", headers: [], body: nil)
        await bus.publish(req)
        let resp = ResponseReceivedEvent(requestID: 1, status: 200,
            headers: [], body: "ok", latencyMs: 10, isMock: false)
        await bus.publish(resp)
        await waitUntil { self.store.currentStepCount == 1 }

        let saved = store.stop()
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.name, name)
        XCTAssertEqual(saved?.steps.count, 1)

        // Reload debería verla en la lista.
        store.reload()
        XCTAssertTrue(store.recordings.contains(name))

        // Load la retrieva del disco.
        let loaded = store.load(name: name)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.steps.count, 1)

        // Cleanup.
        store.delete(name: name)
    }

    @MainActor
    func test_delete_removesFromDisk() async throws {
        let name = "test-delete-\(UUID().uuidString)"
        store.start(name: name)
        _ = store.stop()
        XCTAssertTrue(store.recordings.contains(name))
        store.delete(name: name)
        XCTAssertFalse(store.recordings.contains(name))
    }

    // MARK: - Helpers

    /// Poll con timeout hasta que una condición sea true. Usado en lugar de
    /// `Task.sleep(fixed)` que era flaky en CI macos-14 con load alta.
    @MainActor
    fileprivate func waitUntil(timeout: TimeInterval = 3.0, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
    }
}

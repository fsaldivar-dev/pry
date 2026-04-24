import XCTest
@testable import PryApp
import PryLib

@available(macOS 14, *)
final class BreakpointsStoreTests: XCTestCase {
    var store: BreakpointsStore!
    var bus: EventBus!
    var tempDir: URL!
    var storagePath: String!

    @MainActor
    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storagePath = tempDir.appendingPathComponent("breakpoints").path
        bus = EventBus()
        store = BreakpointsStore(storagePath: storagePath, bus: bus)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - patterns CRUD

    @MainActor
    func test_add_appendsPattern() {
        store.add("/api/login")
        XCTAssertEqual(store.patterns, ["/api/login"])
    }

    @MainActor
    func test_add_deduplicates() {
        store.add("/api")
        store.add("/api")
        XCTAssertEqual(store.patterns.count, 1)
    }

    @MainActor
    func test_add_ignoresEmptyAndTrims() {
        store.add("   ")
        store.add("  /api  ")
        XCTAssertEqual(store.patterns, ["/api"])
    }

    @MainActor
    func test_remove_removesPattern() {
        store.add("/a")
        store.add("/b")
        store.remove("/a")
        XCTAssertEqual(store.patterns, ["/b"])
    }

    @MainActor
    func test_clearAll_emptiesList() {
        store.add("/a")
        store.clearAll()
        XCTAssertTrue(store.patterns.isEmpty)
    }

    // MARK: - matching

    @MainActor
    func test_isMatch_substringUrl() {
        store.add("/api/login")
        XCTAssertTrue(store.isMatch(url: "/api/login?foo=1", host: "x.com"))
    }

    @MainActor
    func test_isMatch_host() {
        store.add("myapp.com")
        XCTAssertTrue(store.isMatch(url: "/", host: "api.myapp.com"))
    }

    @MainActor
    func test_isMatch_glob() {
        store.add("*.myapp.com")
        XCTAssertTrue(store.isMatch(url: "/", host: "api.myapp.com"))
        XCTAssertFalse(store.isMatch(url: "/", host: "other.com"))
    }

    @MainActor
    func test_isMatch_noMatch() {
        store.add("/api")
        XCTAssertFalse(store.isMatch(url: "/users", host: "other.com"))
    }

    // MARK: - persistence

    @MainActor
    func test_persistence_survivesReload() {
        store.add("/persist")
        let reloaded = BreakpointsStore(storagePath: storagePath, bus: bus)
        XCTAssertEqual(reloaded.patterns, ["/persist"])
    }

    // MARK: - pause/resolve flow

    @MainActor
    func test_enqueueAndResolve_resume_returnsPass() async {
        let ctx = RequestContext(method: "GET", host: "h.com", path: "/p")
        let task = Task { await store.enqueue(ctx: ctx) }
        await waitUntil { [self] in !store.pausedRequests.isEmpty }
        XCTAssertEqual(store.pausedRequests.count, 1)
        store.resolve(id: ctx.id, action: .resume)
        let result = await task.value
        switch result {
        case .pass: break
        default: XCTFail("expected .pass, got \(result)")
        }
        XCTAssertTrue(store.pausedRequests.isEmpty)
    }

    @MainActor
    func test_enqueueAndResolve_cancel_returnsShortCircuit() async {
        let ctx = RequestContext(method: "GET", host: "h.com", path: "/p")
        let task = Task { await store.enqueue(ctx: ctx) }
        await waitUntil { [self] in !store.pausedRequests.isEmpty }
        store.resolve(id: ctx.id, action: .cancel)
        let result = await task.value
        switch result {
        case .shortCircuit(let response):
            XCTAssertEqual(response.status, 403)
        default:
            XCTFail("expected .shortCircuit, got \(result)")
        }
    }

    @MainActor
    func test_enqueueAndResolve_modifyHeaders_returnsTransformWithMutation() async {
        let ctx = RequestContext(method: "GET", host: "h.com", path: "/p", headers: ["A": "1"])
        let task = Task { await store.enqueue(ctx: ctx) }
        await waitUntil { [self] in !store.pausedRequests.isEmpty }
        store.resolve(id: ctx.id, action: .modify(headers: [("B", "2")], body: nil))
        let result = await task.value
        switch result {
        case .transform(let newCtx):
            XCTAssertEqual(newCtx.headers["A"], "1", "headers originales preservados")
            XCTAssertEqual(newCtx.headers["B"], "2", "header agregado por modify")
        default:
            XCTFail("expected .transform, got \(result)")
        }
    }

    @MainActor
    func test_resolveAll_resumesEveryPending() async {
        let ctxA = RequestContext(method: "GET", host: "h.com", path: "/a")
        let ctxB = RequestContext(method: "GET", host: "h.com", path: "/b")
        let tA = Task { await store.enqueue(ctx: ctxA) }
        let tB = Task { await store.enqueue(ctx: ctxB) }
        await waitUntil { [self] in store.pausedRequests.count == 2 }
        store.resolveAll(action: .resume)
        _ = await tA.value
        _ = await tB.value
        XCTAssertTrue(store.pausedRequests.isEmpty)
    }

    @MainActor
    func test_resolve_unknownId_isNoOp() {
        store.resolve(id: UUID(), action: .resume) // no debe crashear
    }

    // MARK: - helpers

    @MainActor
    private func waitUntil(timeout: TimeInterval = 2.0, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

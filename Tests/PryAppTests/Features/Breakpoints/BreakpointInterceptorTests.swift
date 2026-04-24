import XCTest
@testable import PryApp
import PryLib

@available(macOS 14, *)
final class BreakpointInterceptorTests: XCTestCase {
    var store: BreakpointsStore!
    var bus: EventBus!
    var sut: BreakpointInterceptor!
    var tempDir: URL!

    @MainActor
    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bus = EventBus()
        store = BreakpointsStore(
            storagePath: tempDir.appendingPathComponent("bp").path,
            bus: bus
        )
        sut = BreakpointInterceptor(store: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_phase_isGate() {
        XCTAssertEqual(sut.phase, .gate)
    }

    func test_pass_whenNoPattern() async {
        let ctx = RequestContext(method: "GET", host: "x.com", path: "/api")
        let result = await sut.intercept(ctx)
        switch result {
        case .pass: break
        default: XCTFail("esperaba .pass, obtuvo \(result)")
        }
    }

    @MainActor
    func test_pause_whenPatternMatches() async {
        store.add("/api")
        let ctx = RequestContext(method: "GET", host: "x.com", path: "/api/users")
        let result = await sut.intercept(ctx)
        switch result {
        case .pause:
            break // éxito — se retornó .pause
        default:
            XCTFail("esperaba .pause, obtuvo \(result)")
        }
    }

    @MainActor
    func test_pauseResolution_awaitsStoreResolve() async {
        store.add("/api")
        let ctx = RequestContext(method: "GET", host: "x.com", path: "/api/users")
        let result = await sut.intercept(ctx)
        guard case .pause(let resolution) = result else {
            XCTFail("esperaba .pause")
            return
        }
        let resolveTask = Task { await resolution() }
        await waitUntil { [self] in !store.pausedRequests.isEmpty }
        store.resolve(id: ctx.id, action: .resume)
        let resolved = await resolveTask.value
        switch resolved {
        case .pass: break
        default: XCTFail("resolution debió retornar .pass, obtuvo \(resolved)")
        }
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 2.0, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

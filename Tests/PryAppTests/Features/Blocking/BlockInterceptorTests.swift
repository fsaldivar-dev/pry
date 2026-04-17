import XCTest
@testable import PryApp
import PryLib

@available(macOS 14, *)
final class BlockInterceptorTests: XCTestCase {
    var store: BlockStore!
    var bus: EventBus!
    var sut: BlockInterceptor!
    var tempDir: URL!

    @MainActor
    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bus = EventBus()
        store = BlockStore(
            storagePath: tempDir.appendingPathComponent("blocklist").path,
            bus: bus
        )
        sut = BlockInterceptor(store: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - phase

    func test_phase_isGate() {
        XCTAssertEqual(sut.phase, .gate)
    }

    // MARK: - pass

    func test_pass_whenHostNotBlocked() async {
        // store vacío → ningún host bloqueado.
        let ctx = RequestContext(method: "GET", host: "example.com", path: "/api")
        let result = await sut.intercept(ctx)
        switch result {
        case .pass:
            break
        default:
            XCTFail("esperaba .pass cuando host no está bloqueado, obtuvo \(result)")
        }
    }

    // MARK: - shortCircuit

    @MainActor
    func test_shortCircuit_whenHostBlocked() async {
        store.add("blocked.com")
        let ctx = RequestContext(method: "GET", host: "blocked.com", path: "/")
        let result = await sut.intercept(ctx)
        switch result {
        case .shortCircuit(let response):
            XCTAssertEqual(response.status, 403)
        default:
            XCTFail("esperaba .shortCircuit(403), obtuvo \(result)")
        }
    }

    @MainActor
    func test_shortCircuit_respectsWildcards() async {
        store.add("*.example.com")
        let ctx = RequestContext(method: "GET", host: "api.example.com", path: "/")
        let result = await sut.intercept(ctx)
        switch result {
        case .shortCircuit(let response):
            XCTAssertEqual(response.status, 403)
        default:
            XCTFail("esperaba .shortCircuit con wildcard, obtuvo \(result)")
        }
    }
}

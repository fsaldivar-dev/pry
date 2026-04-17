import XCTest
@testable import PryApp
import PryLib

@available(macOS 14, *)
final class StatusOverrideInterceptorTests: XCTestCase {
    var store: StatusOverridesStore!
    var bus: EventBus!
    var sut: StatusOverrideInterceptor!
    var tempDir: URL!

    @MainActor
    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bus = EventBus()
        store = StatusOverridesStore(
            storagePath: tempDir.appendingPathComponent("overrides").path,
            bus: bus
        )
        sut = StatusOverrideInterceptor(store: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - phase

    func test_phase_isResolve() {
        XCTAssertEqual(sut.phase, .resolve)
    }

    // MARK: - pass

    func test_pass_whenNoMatch() async {
        // store vacío → ningún pattern matchea.
        let ctx = RequestContext(method: "GET", host: "example.com", path: "/api/users")
        let result = await sut.intercept(ctx)
        switch result {
        case .pass:
            break
        default:
            XCTFail("esperaba .pass cuando no matchea, obtuvo \(result)")
        }
    }

    // MARK: - shortCircuit

    @MainActor
    func test_shortCircuit_withMatchedStatus() async {
        store.add(pattern: "/api/login", status: 500)
        let ctx = RequestContext(method: "POST", host: "example.com", path: "/api/login")
        let result = await sut.intercept(ctx)
        switch result {
        case .shortCircuit(let response):
            XCTAssertEqual(response.status, 500)
        default:
            XCTFail("esperaba .shortCircuit(500), obtuvo \(result)")
        }
    }

    @MainActor
    func test_shortCircuit_preservesStatusValue() async {
        store.add(pattern: "/api/search", status: 429)
        let ctx = RequestContext(method: "GET", host: "example.com", path: "/api/search?q=x")
        let result = await sut.intercept(ctx)
        switch result {
        case .shortCircuit(let response):
            XCTAssertEqual(response.status, 429)
            XCTAssertEqual(response.headers["Content-Type"], "application/json")
            XCTAssertNotNil(response.body)
            if let body = response.body, let str = String(data: body, encoding: .utf8) {
                XCTAssertTrue(str.contains("x_pry_override"))
            } else {
                XCTFail("body should be decodable JSON")
            }
        default:
            XCTFail("esperaba .shortCircuit(429), obtuvo \(result)")
        }
    }

    @MainActor
    func test_shortCircuit_matchesHost() async {
        store.add(pattern: "tracker.com", status: 503)
        let ctx = RequestContext(method: "GET", host: "ads.tracker.com", path: "/beacon")
        let result = await sut.intercept(ctx)
        switch result {
        case .shortCircuit(let response):
            XCTAssertEqual(response.status, 503)
        default:
            XCTFail("esperaba .shortCircuit(503) por match de host, obtuvo \(result)")
        }
    }
}

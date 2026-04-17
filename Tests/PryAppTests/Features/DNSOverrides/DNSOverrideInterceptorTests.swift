import XCTest
@testable import PryApp
import PryLib

@available(macOS 14, *)
final class DNSOverrideInterceptorTests: XCTestCase {
    var store: DNSOverridesStore!
    var bus: EventBus!
    var sut: DNSOverrideInterceptor!
    var tempDir: URL!

    @MainActor
    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bus = EventBus()
        store = DNSOverridesStore(
            storagePath: tempDir.appendingPathComponent("dns").path,
            bus: bus
        )
        sut = DNSOverrideInterceptor(store: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - phase

    func test_phase_isNetwork() {
        XCTAssertEqual(sut.phase, .network)
    }

    // MARK: - pass

    func test_pass_whenNoOverride() async {
        let ctx = RequestContext(method: "GET", host: "api.example.com", path: "/v1/users")
        let result = await sut.intercept(ctx)
        switch result {
        case .pass:
            break
        default:
            XCTFail("esperaba .pass cuando no hay override, obtuvo \(result)")
        }
    }

    // MARK: - transform

    @MainActor
    func test_transform_replacesHostWithIP() async {
        store.add(domain: "api.example.com", ip: "127.0.0.1")
        let ctx = RequestContext(method: "GET", host: "api.example.com", path: "/v1/users")
        let result = await sut.intercept(ctx)
        switch result {
        case .transform(let mutated):
            XCTAssertEqual(mutated.host, "127.0.0.1")
            // Path y método se preservan.
            XCTAssertEqual(mutated.path, "/v1/users")
            XCTAssertEqual(mutated.method, "GET")
        default:
            XCTFail("esperaba .transform, obtuvo \(result)")
        }
    }

    @MainActor
    func test_transform_preservesOriginalHostInHostHeader() async {
        store.add(domain: "api.example.com", ip: "127.0.0.1")
        let ctx = RequestContext(
            method: "GET",
            host: "api.example.com",
            path: "/v1/users",
            headers: ["Accept": "application/json"]
        )
        let result = await sut.intercept(ctx)
        switch result {
        case .transform(let mutated):
            XCTAssertEqual(mutated.host, "127.0.0.1")
            XCTAssertEqual(mutated.headers["Host"], "api.example.com")
            // Header existente no se pierde.
            XCTAssertEqual(mutated.headers["Accept"], "application/json")
        default:
            XCTFail("esperaba .transform con Host header, obtuvo \(result)")
        }
    }

    @MainActor
    func test_transform_doesNotOverwriteExistingHostHeader() async {
        store.add(domain: "api.example.com", ip: "127.0.0.1")
        let ctx = RequestContext(
            method: "GET",
            host: "api.example.com",
            path: "/v1/users",
            headers: ["Host": "custom.vhost.com"]
        )
        let result = await sut.intercept(ctx)
        switch result {
        case .transform(let mutated):
            XCTAssertEqual(mutated.host, "127.0.0.1")
            // El Host header pre-existente se respeta.
            XCTAssertEqual(mutated.headers["Host"], "custom.vhost.com")
        default:
            XCTFail("esperaba .transform respetando Host existente, obtuvo \(result)")
        }
    }
}

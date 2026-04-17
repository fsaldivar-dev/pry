import XCTest
@testable import PryApp
import PryLib

@available(macOS 14, *)
final class HeaderRulesInterceptorTests: XCTestCase {
    var store: HeaderRulesStore!
    var bus: EventBus!
    var sut: HeaderRulesInterceptor!
    var tempDir: URL!

    @MainActor
    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bus = EventBus()
        store = HeaderRulesStore(
            storagePath: tempDir.appendingPathComponent("headers").path,
            bus: bus
        )
        sut = HeaderRulesInterceptor(store: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - phase

    func test_phase_isTransform() {
        XCTAssertEqual(sut.phase, .transform)
    }

    // MARK: - pass

    func test_pass_whenStoreEmpty() async {
        let ctx = RequestContext(
            method: "GET",
            host: "example.com",
            path: "/",
            headers: ["Host": "example.com"]
        )
        let result = await sut.intercept(ctx)
        switch result {
        case .pass: break
        default: XCTFail("esperaba .pass con store vacío, obtuvo \(result)")
        }
    }

    @MainActor
    func test_pass_whenRulesDoNotChangeHeaders() async {
        // remove de un header que no existe → apply retorna la misma collection.
        store.addRemove(name: "X-Not-Present")
        let ctx = RequestContext(
            method: "GET",
            host: "example.com",
            path: "/",
            headers: ["Host": "example.com"]
        )
        let result = await sut.intercept(ctx)
        switch result {
        case .pass: break
        default: XCTFail("esperaba .pass cuando reglas son no-op, obtuvo \(result)")
        }
    }

    // MARK: - transform

    @MainActor
    func test_transform_addsHeaderWhenSetRulePresent() async {
        store.addSet(name: "Authorization", value: "Bearer dev-token")
        let ctx = RequestContext(
            method: "GET",
            host: "example.com",
            path: "/api",
            headers: ["Host": "example.com"]
        )
        let result = await sut.intercept(ctx)
        switch result {
        case .transform(let newCtx):
            XCTAssertEqual(newCtx.headers["Authorization"], "Bearer dev-token")
            XCTAssertEqual(newCtx.headers["Host"], "example.com")
        default:
            XCTFail("esperaba .transform con Authorization agregado, obtuvo \(result)")
        }
    }

    @MainActor
    func test_transform_removesHeaderWhenRemoveRulePresent() async {
        store.addRemove(name: "Cookie")
        let ctx = RequestContext(
            method: "GET",
            host: "example.com",
            path: "/api",
            headers: ["Cookie": "sess=abc", "Host": "example.com"]
        )
        let result = await sut.intercept(ctx)
        switch result {
        case .transform(let newCtx):
            XCTAssertNil(newCtx.headers["Cookie"])
            XCTAssertEqual(newCtx.headers["Host"], "example.com")
        default:
            XCTFail("esperaba .transform con Cookie removido, obtuvo \(result)")
        }
    }

    @MainActor
    func test_transform_preservesOtherCtxFields() async {
        store.addSet(name: "X-Debug", value: "1")
        let originalID = UUID()
        let captured = Date(timeIntervalSince1970: 1_000_000)
        let ctx = RequestContext(
            id: originalID,
            method: "POST",
            host: "api.example.com",
            path: "/v1/users?id=42",
            port: 8443,
            headers: ["Host": "api.example.com"],
            bodyRef: nil,
            capturedAt: captured
        )
        let result = await sut.intercept(ctx)
        switch result {
        case .transform(let newCtx):
            XCTAssertEqual(newCtx.id, originalID)
            XCTAssertEqual(newCtx.method, "POST")
            XCTAssertEqual(newCtx.host, "api.example.com")
            XCTAssertEqual(newCtx.path, "/v1/users?id=42")
            XCTAssertEqual(newCtx.port, 8443)
            XCTAssertEqual(newCtx.capturedAt, captured)
            XCTAssertEqual(newCtx.headers["X-Debug"], "1")
        default:
            XCTFail("esperaba .transform preservando fields, obtuvo \(result)")
        }
    }
}

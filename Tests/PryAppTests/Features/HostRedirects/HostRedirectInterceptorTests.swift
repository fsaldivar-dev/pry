import XCTest
@testable import PryApp
import PryLib

@available(macOS 14, *)
final class HostRedirectInterceptorTests: XCTestCase {
    var store: HostRedirectsStore!
    var bus: EventBus!
    var sut: HostRedirectInterceptor!
    var tempDir: URL!

    @MainActor
    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bus = EventBus()
        store = HostRedirectsStore(
            storagePath: tempDir.appendingPathComponent("redirects").path,
            bus: bus
        )
        sut = HostRedirectInterceptor(store: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - phase

    func test_phase_isNetwork() {
        XCTAssertEqual(sut.phase, .network)
    }

    // MARK: - pass

    func test_pass_whenNoMatch() async {
        let ctx = RequestContext(method: "GET", host: "unrelated.com", path: "/x")
        let result = await sut.intercept(ctx)
        switch result {
        case .pass:
            break
        default:
            XCTFail("esperaba .pass cuando no matchea, obtuvo \(result)")
        }
    }

    // MARK: - transform

    @MainActor
    func test_transform_updatesHost() async {
        store.add(source: "api.test.com", target: "api.stage.com")
        let ctx = RequestContext(method: "GET", host: "api.test.com", path: "/v1/users")
        let result = await sut.intercept(ctx)
        switch result {
        case .transform(let mutated):
            XCTAssertEqual(mutated.host, "api.stage.com")
        default:
            XCTFail("esperaba .transform con host nuevo, obtuvo \(result)")
        }
    }

    @MainActor
    func test_transform_preservesOtherFields() async {
        store.add(source: "api.test.com", target: "api.stage.com")
        let originalID = UUID()
        let originalDate = Date(timeIntervalSince1970: 1_000_000)
        let bodyData = Data("hello".utf8)
        let ctx = RequestContext(
            id: originalID,
            method: "POST",
            host: "api.test.com",
            path: "/v1/login?x=1",
            port: 8443,
            headers: ["Content-Type": "application/json", "X-Custom": "abc"],
            bodyRef: BodyRef(contentLength: bodyData.count, read: { bodyData }),
            capturedAt: originalDate
        )
        let result = await sut.intercept(ctx)
        switch result {
        case .transform(let mutated):
            XCTAssertEqual(mutated.id, originalID)
            XCTAssertEqual(mutated.method, "POST")
            XCTAssertEqual(mutated.path, "/v1/login?x=1")
            XCTAssertEqual(mutated.port, 8443)
            XCTAssertEqual(mutated.capturedAt, originalDate)
            XCTAssertEqual(mutated.headers["Content-Type"], "application/json")
            XCTAssertEqual(mutated.headers["X-Custom"], "abc")
            XCTAssertNotNil(mutated.bodyRef)
            if let ref = mutated.bodyRef {
                let data = try? await ref.read()
                XCTAssertEqual(data, bodyData)
            }
        default:
            XCTFail("esperaba .transform, obtuvo \(result)")
        }
    }

    @MainActor
    func test_transform_updatesHostHeaderIfPresent() async {
        store.add(source: "api.test.com", target: "api.stage.com")
        let ctx = RequestContext(
            method: "GET",
            host: "api.test.com",
            path: "/x",
            headers: ["Host": "api.test.com", "Accept": "*/*"]
        )
        let result = await sut.intercept(ctx)
        switch result {
        case .transform(let mutated):
            XCTAssertEqual(mutated.host, "api.stage.com")
            XCTAssertEqual(mutated.headers["Host"], "api.stage.com")
            XCTAssertEqual(mutated.headers["Accept"], "*/*")
        default:
            XCTFail("esperaba .transform con Host header actualizado, obtuvo \(result)")
        }
    }

    @MainActor
    func test_transform_updatesHostHeaderCaseInsensitiveKey() async {
        store.add(source: "api.test.com", target: "api.stage.com")
        // Cliente envía "host" lowercase — debemos actualizar respetando la key original.
        let ctx = RequestContext(
            method: "GET",
            host: "api.test.com",
            path: "/x",
            headers: ["host": "api.test.com"]
        )
        let result = await sut.intercept(ctx)
        switch result {
        case .transform(let mutated):
            XCTAssertEqual(mutated.headers["host"], "api.stage.com")
            XCTAssertNil(mutated.headers["Host"])
        default:
            XCTFail("esperaba .transform, obtuvo \(result)")
        }
    }

    @MainActor
    func test_transform_noHostHeaderStillTransforms() async {
        store.add(source: "api.test.com", target: "api.stage.com")
        let ctx = RequestContext(
            method: "GET",
            host: "api.test.com",
            path: "/x",
            headers: ["Accept": "*/*"]
        )
        let result = await sut.intercept(ctx)
        switch result {
        case .transform(let mutated):
            XCTAssertEqual(mutated.host, "api.stage.com")
            XCTAssertNil(mutated.headers["Host"])
            XCTAssertEqual(mutated.headers["Accept"], "*/*")
        default:
            XCTFail("esperaba .transform, obtuvo \(result)")
        }
    }
}

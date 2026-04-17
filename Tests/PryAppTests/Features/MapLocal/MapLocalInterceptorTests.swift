import XCTest
@testable import PryApp
import PryLib

@available(macOS 14, *)
final class MapLocalInterceptorTests: XCTestCase {
    var store: MapLocalStore!
    var bus: EventBus!
    var sut: MapLocalInterceptor!
    var tempDir: URL!

    @MainActor
    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bus = EventBus()
        store = MapLocalStore(
            storagePath: tempDir.appendingPathComponent("maps").path,
            bus: bus
        )
        sut = MapLocalInterceptor(store: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_phase_isResolve() {
        XCTAssertEqual(sut.phase, .resolve)
    }

    func test_pass_whenNoMatch() async {
        let ctx = RequestContext(method: "GET", host: "example.com", path: "/api")
        let result = await sut.intercept(ctx)
        guard case .pass = result else {
            XCTFail("esperaba .pass, obtuvo \(result)"); return
        }
    }

    @MainActor
    func test_shortCircuit_withFileContent() async {
        let jsonPath = tempDir.appendingPathComponent("users.json").path
        let jsonContent = #"{"users":[{"id":1,"name":"Alice"}]}"#
        try? jsonContent.write(toFile: jsonPath, atomically: true, encoding: .utf8)

        store.add(pattern: ".*/api/users$", filePath: jsonPath)
        let ctx = RequestContext(method: "GET", host: "example.com", path: "/api/users")
        let result = await sut.intercept(ctx)

        guard case .shortCircuit(let response) = result else {
            XCTFail("esperaba .shortCircuit, obtuvo \(result)"); return
        }
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.headers["Content-Type"], "application/json")
        XCTAssertEqual(String(data: response.body ?? Data(), encoding: .utf8), jsonContent)
    }

    @MainActor
    func test_shortCircuit_withNotFoundWhenFileMissing() async {
        store.add(pattern: ".*", filePath: "/definitely/does/not/exist.json")
        let ctx = RequestContext(method: "GET", host: "example.com", path: "/anything")
        let result = await sut.intercept(ctx)
        guard case .shortCircuit(let response) = result else {
            XCTFail("esperaba .shortCircuit(.notFound), obtuvo \(result)"); return
        }
        XCTAssertEqual(response.status, 404)
    }

    @MainActor
    func test_contentType_inferredFromExtension() async {
        let cases: [(ext: String, expected: String)] = [
            ("json", "application/json"),
            ("js", "application/javascript"),
            ("css", "text/css"),
            ("html", "text/html"),
            ("svg", "image/svg+xml"),
            ("png", "image/png")
        ]
        for tc in cases {
            let path = tempDir.appendingPathComponent("f.\(tc.ext)").path
            try? "x".write(toFile: path, atomically: true, encoding: .utf8)
            store.clear()
            store.add(pattern: ".*", filePath: path)
            let ctx = RequestContext(method: "GET", host: "a", path: "/")
            let result = await sut.intercept(ctx)
            guard case .shortCircuit(let response) = result else {
                XCTFail("no shortCircuit para .\(tc.ext)"); continue
            }
            XCTAssertEqual(response.headers["Content-Type"], tc.expected, "ext: .\(tc.ext)")
        }
    }
}

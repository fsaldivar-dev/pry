import XCTest
@testable import PryApp
import PryLib

@available(macOS 14, *)
final class StatusOverridesStoreTests: XCTestCase {
    var store: StatusOverridesStore!
    var bus: EventBus!
    var tempDir: URL!
    var storagePath: String!

    @MainActor
    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storagePath = tempDir.appendingPathComponent("overrides").path
        bus = EventBus()
        store = StatusOverridesStore(storagePath: storagePath, bus: bus)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - add

    @MainActor
    func test_add_appendsOverride() {
        XCTAssertTrue(store.overrides.isEmpty)
        store.add(pattern: "/api/login", status: 500)
        XCTAssertEqual(store.overrides.count, 1)
        XCTAssertEqual(store.overrides[0].pattern, "/api/login")
        XCTAssertEqual(store.overrides[0].status, 500)
    }

    @MainActor
    func test_add_trimsWhitespace() {
        store.add(pattern: "  /api/login  \n", status: 500)
        XCTAssertEqual(store.overrides.first?.pattern, "/api/login")
    }

    @MainActor
    func test_add_ignoresEmpty() {
        store.add(pattern: "", status: 500)
        store.add(pattern: "   ", status: 500)
        XCTAssertTrue(store.overrides.isEmpty)
    }

    @MainActor
    func test_add_dedupReplacesStatus() {
        store.add(pattern: "/api/login", status: 500)
        store.add(pattern: "/api/login", status: 502)
        XCTAssertEqual(store.overrides.count, 1)
        XCTAssertEqual(store.overrides[0].status, 502)
    }

    // MARK: - remove / clear

    @MainActor
    func test_remove_removesOverride() {
        store.add(pattern: "/a", status: 500)
        store.add(pattern: "/b", status: 502)
        store.remove(pattern: "/a")
        XCTAssertEqual(store.overrides.count, 1)
        XCTAssertEqual(store.overrides[0].pattern, "/b")
    }

    @MainActor
    func test_clear_emptiesList() {
        store.add(pattern: "/a", status: 500)
        store.add(pattern: "/b", status: 502)
        store.clear()
        XCTAssertTrue(store.overrides.isEmpty)
    }

    // MARK: - match — exact path substring

    @MainActor
    func test_match_exactPathSubstring() {
        store.add(pattern: "/api/login", status: 500)
        XCTAssertEqual(store.match(url: "/api/login", host: "example.com"), 500)
        XCTAssertEqual(store.match(url: "/api/login?x=1", host: "example.com"), 500)
    }

    @MainActor
    func test_match_noMatchReturnsNil() {
        store.add(pattern: "/api/login", status: 500)
        XCTAssertNil(store.match(url: "/api/logout", host: "example.com"))
    }

    // MARK: - match — glob

    @MainActor
    func test_match_globSubstringFallback() {
        // `*/checkout*` contiene la substring "/checkout" que matchea directo.
        store.add(pattern: "*/checkout*", status: 503)
        XCTAssertEqual(store.match(url: "/api/checkout/step1", host: "shop.com"), 503)
    }

    @MainActor
    func test_match_globAgainstURL() {
        // Sin la substring directa, el branch glob anclado compila regex.
        store.add(pattern: "*admin*", status: 403)
        XCTAssertEqual(store.match(url: "/panel/admin/users", host: "site.com"), 403)
    }

    // MARK: - match — host

    @MainActor
    func test_match_host() {
        store.add(pattern: "tracker.com", status: 404)
        XCTAssertEqual(store.match(url: "/pixel.gif", host: "ads.tracker.com"), 404)
    }

    @MainActor
    func test_match_caseInsensitive() {
        store.add(pattern: "/API/Login", status: 500)
        XCTAssertEqual(store.match(url: "/api/login", host: "example.com"), 500)
    }

    // MARK: - persistence

    @MainActor
    func test_persistence_survivesReload() {
        store.add(pattern: "/api/login", status: 500)
        store.add(pattern: "/api/pay", status: 502)
        let reloaded = StatusOverridesStore(storagePath: storagePath, bus: bus)
        XCTAssertEqual(reloaded.overrides.count, 2)
        XCTAssertEqual(reloaded.overrides[0].pattern, "/api/login")
        XCTAssertEqual(reloaded.overrides[0].status, 500)
        XCTAssertEqual(reloaded.overrides[1].pattern, "/api/pay")
        XCTAssertEqual(reloaded.overrides[1].status, 502)
    }

    @MainActor
    func test_persistence_clearPersists() {
        store.add(pattern: "/a", status: 500)
        store.clear()
        let reloaded = StatusOverridesStore(storagePath: storagePath, bus: bus)
        XCTAssertTrue(reloaded.overrides.isEmpty)
    }
}

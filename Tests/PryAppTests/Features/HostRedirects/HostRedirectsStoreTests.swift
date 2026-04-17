import XCTest
@testable import PryApp
import PryLib

@available(macOS 14, *)
final class HostRedirectsStoreTests: XCTestCase {
    var store: HostRedirectsStore!
    var bus: EventBus!
    var tempDir: URL!
    var storagePath: String!

    @MainActor
    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storagePath = tempDir.appendingPathComponent("redirects").path
        bus = EventBus()
        store = HostRedirectsStore(storagePath: storagePath, bus: bus)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - add

    @MainActor
    func test_add_appendsRedirect() {
        XCTAssertTrue(store.redirects.isEmpty)
        store.add(source: "api.test.com", target: "api.stage.com")
        XCTAssertEqual(store.redirects.count, 1)
        XCTAssertEqual(store.redirects[0].sourceHost, "api.test.com")
        XCTAssertEqual(store.redirects[0].targetHost, "api.stage.com")
    }

    @MainActor
    func test_add_lowercasesAndTrims() {
        store.add(source: "  API.Test.com  \n", target: "  API.Stage.com  \n")
        XCTAssertEqual(store.redirects.first?.sourceHost, "api.test.com")
        XCTAssertEqual(store.redirects.first?.targetHost, "api.stage.com")
    }

    @MainActor
    func test_add_ignoresEmpty() {
        store.add(source: "", target: "api.stage.com")
        store.add(source: "api.test.com", target: "")
        store.add(source: "   ", target: "   ")
        XCTAssertTrue(store.redirects.isEmpty)
    }

    @MainActor
    func test_add_dedupReplacesTarget() {
        store.add(source: "api.test.com", target: "api.stage.com")
        store.add(source: "api.test.com", target: "api.prod.com")
        XCTAssertEqual(store.redirects.count, 1)
        XCTAssertEqual(store.redirects[0].targetHost, "api.prod.com")
    }

    // MARK: - remove / clear

    @MainActor
    func test_remove_removesRedirect() {
        store.add(source: "a.com", target: "a2.com")
        store.add(source: "b.com", target: "b2.com")
        store.remove(source: "a.com")
        XCTAssertEqual(store.redirects.count, 1)
        XCTAssertEqual(store.redirects[0].sourceHost, "b.com")
    }

    @MainActor
    func test_remove_caseInsensitive() {
        store.add(source: "api.test.com", target: "api.stage.com")
        store.remove(source: "API.TEST.COM")
        XCTAssertTrue(store.redirects.isEmpty)
    }

    @MainActor
    func test_clear_emptiesList() {
        store.add(source: "a.com", target: "a2.com")
        store.add(source: "b.com", target: "b2.com")
        store.clear()
        XCTAssertTrue(store.redirects.isEmpty)
    }

    // MARK: - match

    @MainActor
    func test_match_exactHost() {
        store.add(source: "api.test.com", target: "api.stage.com")
        XCTAssertEqual(store.match(host: "api.test.com"), "api.stage.com")
    }

    @MainActor
    func test_match_caseInsensitive() {
        store.add(source: "api.test.com", target: "api.stage.com")
        XCTAssertEqual(store.match(host: "API.Test.COM"), "api.stage.com")
    }

    @MainActor
    func test_match_noMatchReturnsNil() {
        store.add(source: "api.test.com", target: "api.stage.com")
        XCTAssertNil(store.match(host: "other.com"))
    }

    @MainActor
    func test_match_onlyExactNotSubstring() {
        // Legacy MapRemote hace igualdad exacta, no substring. Un subdominio
        // distinto no debe matchear.
        store.add(source: "test.com", target: "stage.com")
        XCTAssertNil(store.match(host: "api.test.com"))
    }

    // MARK: - persistence

    @MainActor
    func test_persistence_survivesReload() {
        store.add(source: "a.com", target: "a2.com")
        store.add(source: "b.com", target: "b2.com")
        let reloaded = HostRedirectsStore(storagePath: storagePath, bus: bus)
        XCTAssertEqual(reloaded.redirects.count, 2)
        XCTAssertEqual(reloaded.redirects[0].sourceHost, "a.com")
        XCTAssertEqual(reloaded.redirects[0].targetHost, "a2.com")
        XCTAssertEqual(reloaded.redirects[1].sourceHost, "b.com")
        XCTAssertEqual(reloaded.redirects[1].targetHost, "b2.com")
    }

    @MainActor
    func test_persistence_clearPersists() {
        store.add(source: "a.com", target: "a2.com")
        store.clear()
        let reloaded = HostRedirectsStore(storagePath: storagePath, bus: bus)
        XCTAssertTrue(reloaded.redirects.isEmpty)
    }

    @MainActor
    func test_persistence_legacyFormatCompatible() throws {
        // Debe leer archivos escritos por el legacy MapRemote (formato idéntico).
        let legacyContent = "api.test.com\tapi.stage.com\ncdn.test.com\tcdn.stage.com\n"
        try legacyContent.write(toFile: storagePath, atomically: true, encoding: .utf8)
        let loaded = HostRedirectsStore(storagePath: storagePath, bus: bus)
        XCTAssertEqual(loaded.redirects.count, 2)
        XCTAssertEqual(loaded.redirects[0].sourceHost, "api.test.com")
        XCTAssertEqual(loaded.redirects[1].targetHost, "cdn.stage.com")
    }
}

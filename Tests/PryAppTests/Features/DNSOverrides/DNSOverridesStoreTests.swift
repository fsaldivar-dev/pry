import XCTest
@testable import PryApp
import PryLib

@available(macOS 14, *)
final class DNSOverridesStoreTests: XCTestCase {
    var store: DNSOverridesStore!
    var bus: EventBus!
    var tempDir: URL!
    var storagePath: String!

    @MainActor
    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storagePath = tempDir.appendingPathComponent("dns").path
        bus = EventBus()
        store = DNSOverridesStore(storagePath: storagePath, bus: bus)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - add

    @MainActor
    func test_add_appendsOverride() {
        XCTAssertTrue(store.overrides.isEmpty)
        store.add(domain: "api.example.com", ip: "127.0.0.1")
        XCTAssertEqual(store.overrides.count, 1)
        XCTAssertEqual(store.overrides[0].domain, "api.example.com")
        XCTAssertEqual(store.overrides[0].ip, "127.0.0.1")
    }

    @MainActor
    func test_add_lowercasesDomainAndTrimsBoth() {
        store.add(domain: "  API.Example.COM  \n", ip: "  10.0.0.1  ")
        XCTAssertEqual(store.overrides.first?.domain, "api.example.com")
        XCTAssertEqual(store.overrides.first?.ip, "10.0.0.1")
    }

    @MainActor
    func test_add_ignoresEmptyDomain() {
        store.add(domain: "", ip: "127.0.0.1")
        store.add(domain: "   ", ip: "127.0.0.1")
        XCTAssertTrue(store.overrides.isEmpty)
    }

    @MainActor
    func test_add_ignoresInvalidIP() {
        // Empty IP.
        store.add(domain: "api.example.com", ip: "")
        XCTAssertTrue(store.overrides.isEmpty)
        // IP sin punto — validación mínima.
        store.add(domain: "api.example.com", ip: "notanip")
        XCTAssertTrue(store.overrides.isEmpty)
    }

    @MainActor
    func test_add_dedupReplacesIP() {
        store.add(domain: "api.example.com", ip: "127.0.0.1")
        store.add(domain: "api.example.com", ip: "10.0.0.2")
        XCTAssertEqual(store.overrides.count, 1)
        XCTAssertEqual(store.overrides[0].ip, "10.0.0.2")
    }

    // MARK: - remove / clear

    @MainActor
    func test_remove_removesOverride() {
        store.add(domain: "a.com", ip: "1.1.1.1")
        store.add(domain: "b.com", ip: "2.2.2.2")
        store.remove(domain: "a.com")
        XCTAssertEqual(store.overrides.count, 1)
        XCTAssertEqual(store.overrides[0].domain, "b.com")
    }

    @MainActor
    func test_remove_caseInsensitive() {
        store.add(domain: "api.example.com", ip: "1.2.3.4")
        store.remove(domain: "API.EXAMPLE.COM")
        XCTAssertTrue(store.overrides.isEmpty)
    }

    @MainActor
    func test_clear_emptiesList() {
        store.add(domain: "a.com", ip: "1.1.1.1")
        store.add(domain: "b.com", ip: "2.2.2.2")
        store.clear()
        XCTAssertTrue(store.overrides.isEmpty)
    }

    // MARK: - resolve

    @MainActor
    func test_resolve_exactMatch() {
        store.add(domain: "api.example.com", ip: "127.0.0.1")
        XCTAssertEqual(store.resolve(host: "api.example.com"), "127.0.0.1")
    }

    @MainActor
    func test_resolve_caseInsensitiveHost() {
        store.add(domain: "api.example.com", ip: "127.0.0.1")
        XCTAssertEqual(store.resolve(host: "API.Example.COM"), "127.0.0.1")
    }

    @MainActor
    func test_resolve_noMatchReturnsNil() {
        store.add(domain: "api.example.com", ip: "127.0.0.1")
        XCTAssertNil(store.resolve(host: "other.com"))
        // Subdominios: matching es exacto, no prefix.
        XCTAssertNil(store.resolve(host: "sub.api.example.com"))
    }

    // MARK: - persistence

    @MainActor
    func test_persistence_survivesReload() {
        store.add(domain: "a.com", ip: "1.1.1.1")
        store.add(domain: "b.com", ip: "2.2.2.2")
        let reloaded = DNSOverridesStore(storagePath: storagePath, bus: bus)
        XCTAssertEqual(reloaded.overrides.count, 2)
        XCTAssertEqual(reloaded.overrides[0].domain, "a.com")
        XCTAssertEqual(reloaded.overrides[0].ip, "1.1.1.1")
        XCTAssertEqual(reloaded.overrides[1].domain, "b.com")
        XCTAssertEqual(reloaded.overrides[1].ip, "2.2.2.2")
    }

    @MainActor
    func test_persistence_clearPersists() {
        store.add(domain: "a.com", ip: "1.1.1.1")
        store.clear()
        let reloaded = DNSOverridesStore(storagePath: storagePath, bus: bus)
        XCTAssertTrue(reloaded.overrides.isEmpty)
    }
}

import XCTest
@testable import PryApp
import PryLib

@available(macOS 14, *)
final class BlockStoreTests: XCTestCase {
    var store: BlockStore!
    var bus: EventBus!
    var tempDir: URL!
    var storagePath: String!

    @MainActor
    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storagePath = tempDir.appendingPathComponent("blocklist").path
        bus = EventBus()
        store = BlockStore(storagePath: storagePath, bus: bus)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - add

    @MainActor
    func test_add_appendsDomain() {
        XCTAssertTrue(store.domains.isEmpty)
        store.add("example.com")
        XCTAssertEqual(store.domains, ["example.com"])
    }

    @MainActor
    func test_add_lowercasesAndTrims() {
        store.add("  Example.COM\n")
        XCTAssertEqual(store.domains, ["example.com"])
    }

    @MainActor
    func test_add_ignoresEmpty() {
        store.add("")
        store.add("   ")
        XCTAssertTrue(store.domains.isEmpty)
    }

    @MainActor
    func test_add_deduplicates() {
        store.add("example.com")
        store.add("example.com")
        XCTAssertEqual(store.domains.count, 1)
    }

    // MARK: - remove

    @MainActor
    func test_remove_removesDomain() {
        store.add("a.com")
        store.add("b.com")
        store.remove("a.com")
        XCTAssertEqual(store.domains, ["b.com"])
    }

    @MainActor
    func test_remove_nonExistent_isNoOp() {
        store.add("a.com")
        store.remove("nonexistent.com")
        XCTAssertEqual(store.domains, ["a.com"])
    }

    // MARK: - clear

    @MainActor
    func test_clear_emptiesList() {
        store.add("a.com")
        store.add("b.com")
        store.clear()
        XCTAssertTrue(store.domains.isEmpty)
    }

    // MARK: - isBlocked — exact match

    @MainActor
    func test_isBlocked_exactMatch() {
        store.add("example.com")
        XCTAssertTrue(store.isBlocked("example.com"))
    }

    @MainActor
    func test_isBlocked_differentHost_returnsFalse() {
        store.add("example.com")
        XCTAssertFalse(store.isBlocked("other.com"))
    }

    @MainActor
    func test_isBlocked_caseInsensitive() {
        store.add("example.com")
        XCTAssertTrue(store.isBlocked("EXAMPLE.com"))
    }

    // MARK: - isBlocked — wildcard

    @MainActor
    func test_isBlocked_wildcardMatchesSubdomain() {
        store.add("*.example.com")
        XCTAssertTrue(store.isBlocked("api.example.com"))
        XCTAssertTrue(store.isBlocked("deep.nested.example.com"))
    }

    @MainActor
    func test_isBlocked_wildcardMatchesBaseDomain() {
        store.add("*.example.com")
        XCTAssertTrue(store.isBlocked("example.com"))
    }

    @MainActor
    func test_isBlocked_wildcardDoesNotMatchUnrelated() {
        store.add("*.example.com")
        XCTAssertFalse(store.isBlocked("notexample.com"))
        XCTAssertFalse(store.isBlocked("example.org"))
    }

    // MARK: - persistence

    @MainActor
    func test_persistence_survivesReload() {
        store.add("persistent.com")
        // Segundo store apuntando al mismo archivo — simula reinicio de app.
        let reloaded = BlockStore(storagePath: storagePath, bus: bus)
        XCTAssertEqual(reloaded.domains, ["persistent.com"])
    }

    @MainActor
    func test_persistence_removePersists() {
        store.add("a.com")
        store.add("b.com")
        store.remove("a.com")
        let reloaded = BlockStore(storagePath: storagePath, bus: bus)
        XCTAssertEqual(reloaded.domains, ["b.com"])
    }

    @MainActor
    func test_persistence_clearPersists() {
        store.add("a.com")
        store.clear()
        let reloaded = BlockStore(storagePath: storagePath, bus: bus)
        XCTAssertTrue(reloaded.domains.isEmpty)
    }
}

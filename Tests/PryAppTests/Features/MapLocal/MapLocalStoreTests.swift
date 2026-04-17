import XCTest
@testable import PryApp
import PryLib

@available(macOS 14, *)
final class MapLocalStoreTests: XCTestCase {
    var store: MapLocalStore!
    var bus: EventBus!
    var tempDir: URL!
    var storagePath: String!

    @MainActor
    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storagePath = tempDir.appendingPathComponent("maps").path
        bus = EventBus()
        store = MapLocalStore(storagePath: storagePath, bus: bus)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - add

    @MainActor
    func test_add_appendsMapping() {
        XCTAssertTrue(store.mappings.isEmpty)
        store.add(pattern: "^https://api\\.example\\.com$", filePath: "/tmp/users.json")
        XCTAssertEqual(store.mappings.count, 1)
        XCTAssertEqual(store.mappings[0].pattern, "^https://api\\.example\\.com$")
        XCTAssertEqual(store.mappings[0].filePath, "/tmp/users.json")
    }

    @MainActor
    func test_add_trimsWhitespace() {
        store.add(pattern: "  /api/users  ", filePath: "  /tmp/x.json  \n")
        XCTAssertEqual(store.mappings[0].pattern, "/api/users")
        XCTAssertEqual(store.mappings[0].filePath, "/tmp/x.json")
    }

    @MainActor
    func test_add_ignoresEmpty() {
        store.add(pattern: "", filePath: "/tmp/x.json")
        store.add(pattern: "/api", filePath: "")
        XCTAssertTrue(store.mappings.isEmpty)
    }

    @MainActor
    func test_add_replacesExistingPattern() {
        store.add(pattern: "/api", filePath: "/tmp/a.json")
        store.add(pattern: "/api", filePath: "/tmp/b.json")
        XCTAssertEqual(store.mappings.count, 1)
        XCTAssertEqual(store.mappings[0].filePath, "/tmp/b.json")
    }

    // MARK: - remove / clear

    @MainActor
    func test_remove_removesMapping() {
        store.add(pattern: "/a", filePath: "/tmp/a")
        store.add(pattern: "/b", filePath: "/tmp/b")
        store.remove(pattern: "/a")
        XCTAssertEqual(store.mappings.count, 1)
        XCTAssertEqual(store.mappings[0].pattern, "/b")
    }

    @MainActor
    func test_remove_nonExistent_isNoOp() {
        store.add(pattern: "/a", filePath: "/tmp/a")
        store.remove(pattern: "/nonexistent")
        XCTAssertEqual(store.mappings.count, 1)
    }

    @MainActor
    func test_clear_emptiesList() {
        store.add(pattern: "/a", filePath: "/tmp/a")
        store.add(pattern: "/b", filePath: "/tmp/b")
        store.clear()
        XCTAssertTrue(store.mappings.isEmpty)
    }

    // MARK: - match

    @MainActor
    func test_match_regexExact() {
        store.add(pattern: "^https://api\\.example\\.com/users$", filePath: "/tmp/u.json")
        XCTAssertEqual(store.match(url: "https://api.example.com/users"), "/tmp/u.json")
    }

    @MainActor
    func test_match_regexPartial() {
        store.add(pattern: ".*\\.analytics\\.com.*", filePath: "/tmp/a.json")
        XCTAssertEqual(store.match(url: "https://tracker.analytics.com/pixel"), "/tmp/a.json")
    }

    @MainActor
    func test_match_firstPatternWins() {
        store.add(pattern: ".*", filePath: "/tmp/first.json")
        store.add(pattern: "/api", filePath: "/tmp/second.json")
        XCTAssertEqual(store.match(url: "/api"), "/tmp/first.json")
    }

    @MainActor
    func test_match_noMatchReturnsNil() {
        store.add(pattern: "^/api$", filePath: "/tmp/x.json")
        XCTAssertNil(store.match(url: "/other"))
    }

    @MainActor
    func test_match_invalidRegexIsIgnored() {
        // Regex inválido — se saltea silenciosamente.
        store.add(pattern: "[invalid(", filePath: "/tmp/bad.json")
        store.add(pattern: "^/good$", filePath: "/tmp/good.json")
        XCTAssertEqual(store.match(url: "/good"), "/tmp/good.json")
    }

    // MARK: - persistence

    @MainActor
    func test_persistence_survivesReload() {
        store.add(pattern: "/api", filePath: "/tmp/x.json")
        let reloaded = MapLocalStore(storagePath: storagePath, bus: bus)
        XCTAssertEqual(reloaded.mappings.count, 1)
        XCTAssertEqual(reloaded.mappings[0].pattern, "/api")
        XCTAssertEqual(reloaded.mappings[0].filePath, "/tmp/x.json")
    }

    @MainActor
    func test_persistence_clearPersists() {
        store.add(pattern: "/api", filePath: "/tmp/x.json")
        store.clear()
        let reloaded = MapLocalStore(storagePath: storagePath, bus: bus)
        XCTAssertTrue(reloaded.mappings.isEmpty)
    }
}

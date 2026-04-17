import XCTest
@testable import PryApp
import PryLib

@available(macOS 14, *)
final class HeaderRulesStoreTests: XCTestCase {
    var store: HeaderRulesStore!
    var bus: EventBus!
    var tempDir: URL!
    var storagePath: String!

    @MainActor
    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storagePath = tempDir.appendingPathComponent("headers").path
        bus = EventBus()
        store = HeaderRulesStore(storagePath: storagePath, bus: bus)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - addSet

    @MainActor
    func test_addSet_appendsRule() {
        XCTAssertTrue(store.rules.isEmpty)
        store.addSet(name: "Authorization", value: "Bearer dev")
        XCTAssertEqual(store.rules.count, 1)
        XCTAssertEqual(store.rules[0].action, .set)
        XCTAssertEqual(store.rules[0].name, "Authorization")
        XCTAssertEqual(store.rules[0].value, "Bearer dev")
    }

    @MainActor
    func test_addSet_trimsName() {
        store.addSet(name: "  X-Debug  ", value: "true")
        XCTAssertEqual(store.rules.first?.name, "X-Debug")
    }

    @MainActor
    func test_addSet_ignoresEmptyName() {
        store.addSet(name: "", value: "v")
        store.addSet(name: "   ", value: "v")
        XCTAssertTrue(store.rules.isEmpty)
    }

    @MainActor
    func test_addSet_dedupReplacesValueCaseInsensitive() {
        store.addSet(name: "Authorization", value: "old")
        store.addSet(name: "authorization", value: "new")
        XCTAssertEqual(store.rules.count, 1)
        XCTAssertEqual(store.rules[0].value, "new")
    }

    // MARK: - addRemove

    @MainActor
    func test_addRemove_appendsRule() {
        store.addRemove(name: "Cookie")
        XCTAssertEqual(store.rules.count, 1)
        XCTAssertEqual(store.rules[0].action, .remove)
        XCTAssertEqual(store.rules[0].name, "Cookie")
    }

    @MainActor
    func test_addRemove_dedupCaseInsensitive() {
        store.addRemove(name: "Cookie")
        store.addRemove(name: "cookie")
        XCTAssertEqual(store.rules.count, 1)
    }

    @MainActor
    func test_addRemove_ignoresEmptyName() {
        store.addRemove(name: "")
        store.addRemove(name: "   ")
        XCTAssertTrue(store.rules.isEmpty)
    }

    // MARK: - remove / clear

    @MainActor
    func test_remove_removesSpecificRule() {
        store.addSet(name: "A", value: "1")
        store.addSet(name: "B", value: "2")
        let first = store.rules[0]
        store.remove(rule: first)
        XCTAssertEqual(store.rules.count, 1)
        XCTAssertEqual(store.rules[0].name, "B")
    }

    @MainActor
    func test_clear_emptiesList() {
        store.addSet(name: "A", value: "1")
        store.addRemove(name: "B")
        store.clear()
        XCTAssertTrue(store.rules.isEmpty)
    }

    // MARK: - apply

    @MainActor
    func test_apply_emptyRulesReturnsHeadersUnchanged() {
        let headers = ["Host": "example.com"]
        XCTAssertEqual(store.apply(to: headers), headers)
    }

    @MainActor
    func test_apply_setAddsHeaderToEmpty() {
        store.addSet(name: "X-Debug", value: "true")
        let result = store.apply(to: [:])
        XCTAssertEqual(result, ["X-Debug": "true"])
    }

    @MainActor
    func test_apply_setReplacesExistingCaseInsensitive() {
        store.addSet(name: "Authorization", value: "Bearer new")
        // La request viene con el header en lowercase — debe ser reemplazado.
        let input = ["authorization": "Bearer old", "Host": "example.com"]
        let result = store.apply(to: input)
        XCTAssertEqual(result["Authorization"], "Bearer new")
        XCTAssertNil(result["authorization"])
        XCTAssertEqual(result["Host"], "example.com")
    }

    @MainActor
    func test_apply_removeDropsHeaderCaseInsensitive() {
        store.addRemove(name: "Cookie")
        let input = ["cookie": "sess=abc", "Host": "example.com"]
        let result = store.apply(to: input)
        XCTAssertNil(result["cookie"])
        XCTAssertNil(result["Cookie"])
        XCTAssertEqual(result["Host"], "example.com")
    }

    @MainActor
    func test_apply_removeOnMissingHeaderIsNoOp() {
        store.addRemove(name: "X-Absent")
        let input = ["Host": "example.com"]
        let result = store.apply(to: input)
        XCTAssertEqual(result, input)
    }

    @MainActor
    func test_apply_multipleRulesInOrder() {
        store.addSet(name: "X-A", value: "1")
        store.addRemove(name: "Cookie")
        store.addSet(name: "X-B", value: "2")
        let input = ["Cookie": "sess", "Host": "h"]
        let result = store.apply(to: input)
        XCTAssertEqual(result["X-A"], "1")
        XCTAssertEqual(result["X-B"], "2")
        XCTAssertNil(result["Cookie"])
        XCTAssertEqual(result["Host"], "h")
    }

    // MARK: - persistence

    @MainActor
    func test_persistence_survivesReload() {
        store.addSet(name: "Authorization", value: "Bearer x")
        store.addRemove(name: "Cookie")
        let reloaded = HeaderRulesStore(storagePath: storagePath, bus: bus)
        XCTAssertEqual(reloaded.rules.count, 2)
        XCTAssertEqual(reloaded.rules[0].action, .set)
        XCTAssertEqual(reloaded.rules[0].name, "Authorization")
        XCTAssertEqual(reloaded.rules[0].value, "Bearer x")
        XCTAssertEqual(reloaded.rules[1].action, .remove)
        XCTAssertEqual(reloaded.rules[1].name, "Cookie")
    }

    @MainActor
    func test_persistence_clearPersists() {
        store.addSet(name: "A", value: "1")
        store.clear()
        let reloaded = HeaderRulesStore(storagePath: storagePath, bus: bus)
        XCTAssertTrue(reloaded.rules.isEmpty)
    }

    @MainActor
    func test_persistence_preservesValueWithSpaces() {
        store.addSet(name: "X-Token", value: "Bearer with spaces and = signs")
        let reloaded = HeaderRulesStore(storagePath: storagePath, bus: bus)
        XCTAssertEqual(reloaded.rules.count, 1)
        XCTAssertEqual(reloaded.rules[0].value, "Bearer with spaces and = signs")
    }
}

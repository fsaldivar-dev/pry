import XCTest
import PryLib
@testable import PryKit

@available(macOS 14, *)
final class BreakpointUIManagerTests: XCTestCase {

    @MainActor
    func testAddRemovePatterns() {
        BreakpointStore.shared.clearAll()

        let manager = BreakpointUIManager()
        manager.add("*/api/*")
        XCTAssertTrue(manager.patterns.contains("*/api/*"))

        manager.remove("*/api/*")
        XCTAssertFalse(manager.patterns.contains("*/api/*"))

        BreakpointStore.shared.clearAll()
    }

    @MainActor
    func testClearAllPatterns() {
        BreakpointStore.shared.clearAll()

        let manager = BreakpointUIManager()
        manager.add("*/a/*")
        manager.add("*/b/*")
        manager.clearAll()
        XCTAssertTrue(manager.patterns.isEmpty)

        BreakpointStore.shared.clearAll()
    }
}

import Testing
import PryLib
@testable import PryKit

@Suite("BreakpointUIManager")
struct BreakpointUIManagerTests {

    @available(macOS 14, *)
    @Test func addRemovePatterns() async {
        // Clean state
        BreakpointStore.shared.clearAll()

        let manager = await BreakpointUIManager()
        await manager.add("*/api/*")
        #expect(await manager.patterns.contains("*/api/*"))

        await manager.remove("*/api/*")
        #expect(await manager.patterns.contains("*/api/*") == false)

        // Cleanup
        BreakpointStore.shared.clearAll()
    }

    @available(macOS 14, *)
    @Test func clearAllPatterns() async {
        BreakpointStore.shared.clearAll()

        let manager = await BreakpointUIManager()
        await manager.add("*/a/*")
        await manager.add("*/b/*")
        await manager.clearAll()
        #expect(await manager.patterns.isEmpty)

        BreakpointStore.shared.clearAll()
    }
}

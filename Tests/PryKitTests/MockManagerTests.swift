import Testing
import PryLib
@testable import PryKit

@Suite("MockManager")
struct MockManagerTests {

    @available(macOS 14, *)
    @Test func saveAndLoad() async {
        let manager = await MockManager()
        Config.clearMocks()

        await manager.save(path: "/api/test", response: #"{"ok":true}"#)
        await manager.reload()
        #expect(await manager.mocks["/api/test"] == #"{"ok":true}"#)

        // Cleanup
        Config.clearMocks()
    }

    @available(macOS 14, *)
    @Test func clearRemovesAll() async {
        let manager = await MockManager()
        Config.clearMocks()

        await manager.save(path: "/a", response: "1")
        await manager.save(path: "/b", response: "2")
        await manager.clearAll()
        #expect(await manager.mocks.isEmpty)
    }
}

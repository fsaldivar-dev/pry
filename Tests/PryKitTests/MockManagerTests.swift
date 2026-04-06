import XCTest
import PryLib
@testable import PryKit

@available(macOS 14, *)
final class MockManagerTests: XCTestCase {

    @MainActor
    func testSaveAndLoad() {
        let manager = MockManager()
        Config.clearMocks()

        manager.save(path: "/api/test", response: #"{"ok":true}"#)
        manager.reload()
        XCTAssertEqual(manager.mocks["/api/test"], #"{"ok":true}"#)

        Config.clearMocks()
    }

    @MainActor
    func testRemoveDeletesSingleMock() {
        let manager = MockManager()
        Config.clearMocks()

        manager.save(path: "/api/a", response: "1")
        manager.save(path: "/api/b", response: "2")
        manager.remove(path: "/api/a")
        XCTAssertNil(manager.mocks["/api/a"])
        XCTAssertEqual(manager.mocks["/api/b"], "2")

        Config.clearMocks()
    }

    @MainActor
    func testClearRemovesAll() {
        let manager = MockManager()
        Config.clearMocks()

        manager.save(path: "/a", response: "1")
        manager.save(path: "/b", response: "2")
        manager.clearAll()
        XCTAssertTrue(manager.mocks.isEmpty)
    }
}

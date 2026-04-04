import XCTest
@testable import PryLib

final class BlockListTests: XCTestCase {
    override func setUp() { super.setUp(); BlockList.clear() }
    override func tearDown() { BlockList.clear(); super.tearDown() }

    func testAddAndLoad() {
        BlockList.add("ads.example.com")
        let all = BlockList.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(all.contains("ads.example.com"))
    }

    func testIsBlocked() {
        BlockList.add("ads.example.com")
        XCTAssertTrue(BlockList.isBlocked("ads.example.com"))
    }

    func testIsNotBlocked() {
        BlockList.add("ads.example.com")
        XCTAssertFalse(BlockList.isBlocked("api.myapp.com"))
    }

    func testClear() {
        BlockList.add("ads.example.com")
        BlockList.clear()
        XCTAssertTrue(BlockList.loadAll().isEmpty)
    }

    func testWildcard() {
        BlockList.add("*.ads.com")
        XCTAssertTrue(BlockList.isBlocked("tracker.ads.com"))
        XCTAssertFalse(BlockList.isBlocked("myapp.com"))
    }
}

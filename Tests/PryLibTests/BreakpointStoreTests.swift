import XCTest
@testable import PryLib

final class BreakpointStoreTests: XCTestCase {
    private var store: BreakpointStore!

    override func setUp() {
        super.setUp()
        store = BreakpointStore()
        store.clearAll()
    }

    override func tearDown() {
        store.clearAll()
        super.tearDown()
    }

    func testAddAndList() {
        store.add("/api/login")
        store.add("/api/users")
        let patterns = store.all()
        XCTAssertEqual(patterns.count, 2)
        XCTAssertTrue(patterns.contains("/api/login"))
        XCTAssertTrue(patterns.contains("/api/users"))
    }

    func testNoDuplicates() {
        store.add("/api/login")
        store.add("/api/login")
        XCTAssertEqual(store.all().count, 1)
    }

    func testRemove() {
        store.add("/api/login")
        store.add("/api/users")
        store.remove("/api/login")
        let patterns = store.all()
        XCTAssertEqual(patterns.count, 1)
        XCTAssertFalse(patterns.contains("/api/login"))
    }

    func testClearAll() {
        store.add("/api/login")
        store.add("/api/users")
        store.clearAll()
        XCTAssertTrue(store.all().isEmpty)
    }

    func testShouldBreakSimplePrefix() {
        store.add("/api/login")
        XCTAssertTrue(store.shouldBreak(url: "/api/login", host: "example.com"))
        XCTAssertFalse(store.shouldBreak(url: "/api/other", host: "example.com"))
    }

    func testShouldBreakHostMatch() {
        store.add("api.myapp.com")
        XCTAssertTrue(store.shouldBreak(url: "/whatever", host: "api.myapp.com"))
        XCTAssertFalse(store.shouldBreak(url: "/whatever", host: "other.com"))
    }

    func testShouldBreakGlob() {
        store.add("*.myapp.com")
        XCTAssertTrue(store.shouldBreak(url: "/test", host: "api.myapp.com"))
        XCTAssertTrue(store.shouldBreak(url: "/test", host: "staging.myapp.com"))
        XCTAssertFalse(store.shouldBreak(url: "/test", host: "other.com"))
    }
}

import XCTest
@testable import PryLib

final class StatusOverrideStoreTests: XCTestCase {
    override func setUp() { super.setUp(); StatusOverrideStore.clear() }
    override func tearDown() { StatusOverrideStore.clear(); super.tearDown() }

    func testSaveAndLoad() {
        StatusOverrideStore.save(pattern: "/api/login", status: 401)
        let overrides = StatusOverrideStore.loadAll()
        XCTAssertEqual(overrides.count, 1)
        XCTAssertEqual(overrides[0].pattern, "/api/login")
        XCTAssertEqual(overrides[0].status, 401)
    }

    func testMultipleOverrides() {
        StatusOverrideStore.save(pattern: "/api/login", status: 401)
        StatusOverrideStore.save(pattern: "/api/pay", status: 500)
        let overrides = StatusOverrideStore.loadAll()
        XCTAssertEqual(overrides.count, 2)
    }

    func testMatchExact() {
        StatusOverrideStore.save(pattern: "/api/login", status: 403)
        XCTAssertEqual(StatusOverrideStore.match(url: "/api/login", host: "example.com"), 403)
    }

    func testMatchGlob() {
        StatusOverrideStore.save(pattern: "/api/*", status: 500)
        XCTAssertEqual(StatusOverrideStore.match(url: "/api/users", host: "example.com"), 500)
    }

    func testNoMatch() {
        StatusOverrideStore.save(pattern: "/api/login", status: 401)
        XCTAssertNil(StatusOverrideStore.match(url: "/other", host: "example.com"))
    }

    func testRemove() {
        StatusOverrideStore.save(pattern: "/api/login", status: 401)
        StatusOverrideStore.save(pattern: "/api/pay", status: 500)
        StatusOverrideStore.remove(pattern: "/api/login")
        let overrides = StatusOverrideStore.loadAll()
        XCTAssertEqual(overrides.count, 1)
        XCTAssertEqual(overrides[0].pattern, "/api/pay")
    }

    func testClear() {
        StatusOverrideStore.save(pattern: "/api/login", status: 401)
        StatusOverrideStore.clear()
        XCTAssertTrue(StatusOverrideStore.loadAll().isEmpty)
    }
}

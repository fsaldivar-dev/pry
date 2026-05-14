import XCTest
@testable import PryLib

final class MapRemoteTests: XCTestCase {
    override func setUp() { super.setUp(); MapRemote.clear() }
    override func tearDown() { MapRemote.clear(); super.tearDown() }

    func testSaveAndLoad() {
        MapRemote.save(sourceHost: "api.prod.com", targetHost: "api.staging.com")
        let all = MapRemote.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].sourceHost, "api.prod.com")
        XCTAssertEqual(all[0].targetHost, "api.staging.com")
    }

    func testMatch() {
        MapRemote.save(sourceHost: "api.prod.com", targetHost: "api.staging.com")
        XCTAssertEqual(MapRemote.match(host: "api.prod.com"), "api.staging.com")
    }

    func testNoMatch() {
        MapRemote.save(sourceHost: "api.prod.com", targetHost: "api.staging.com")
        XCTAssertNil(MapRemote.match(host: "other.com"))
    }

    func testClear() {
        MapRemote.save(sourceHost: "api.prod.com", targetHost: "api.staging.com")
        MapRemote.clear()
        XCTAssertTrue(MapRemote.loadAll().isEmpty)
    }

    func testCaseInsensitive() {
        MapRemote.save(sourceHost: "api.prod.com", targetHost: "api.staging.com")
        XCTAssertEqual(MapRemote.match(host: "API.PROD.COM"), "api.staging.com")
    }
}

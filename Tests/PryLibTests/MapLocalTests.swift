import XCTest
@testable import PryLib

final class MapLocalTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MapLocal.clear()
    }

    override func tearDown() {
        MapLocal.clear()
        super.tearDown()
    }

    func testSaveAndLoad() {
        MapLocal.save(regex: "/api/v1/.*", filePath: "/tmp/mock.json")
        let maps = MapLocal.loadAll()
        XCTAssertEqual(maps.count, 1)
        XCTAssertEqual(maps[0].regex, "/api/v1/.*")
        XCTAssertEqual(maps[0].filePath, "/tmp/mock.json")
    }

    func testRegexMatch() {
        MapLocal.save(regex: "/api/v1/.*", filePath: "/tmp/mock.json")
        XCTAssertNotNil(MapLocal.match(url: "/api/v1/users"))
        XCTAssertNotNil(MapLocal.match(url: "/api/v1/users/123"))
        XCTAssertNil(MapLocal.match(url: "/api/v2/users"))
    }

    func testRegexNoMatch() {
        MapLocal.save(regex: "/exact/path", filePath: "/tmp/mock.json")
        XCTAssertNil(MapLocal.match(url: "/other/path"))
    }

    func testClear() {
        MapLocal.save(regex: "/api/.*", filePath: "/tmp/a.json")
        MapLocal.save(regex: "/web/.*", filePath: "/tmp/b.json")
        MapLocal.clear()
        XCTAssertTrue(MapLocal.loadAll().isEmpty)
    }

    func testMultipleMaps() {
        MapLocal.save(regex: "/api/.*", filePath: "/tmp/api.json")
        MapLocal.save(regex: "/web/.*", filePath: "/tmp/web.json")
        let apiMatch = MapLocal.match(url: "/api/users")
        let webMatch = MapLocal.match(url: "/web/index")
        XCTAssertEqual(apiMatch, "/tmp/api.json")
        XCTAssertEqual(webMatch, "/tmp/web.json")
    }
}

import XCTest
@testable import PryLib

final class WatchlistTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(atPath: Watchlist.watchFile)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: Watchlist.watchFile)
        super.tearDown()
    }

    func testAddAndMatch() {
        Watchlist.add("api.example.com")
        XCTAssertTrue(Watchlist.matches("api.example.com"))
        XCTAssertFalse(Watchlist.matches("other.com"))
    }

    func testRemove() {
        Watchlist.add("api.example.com")
        Watchlist.remove("api.example.com")
        XCTAssertFalse(Watchlist.matches("api.example.com"))
    }

    func testWildcard() {
        Watchlist.add("*.example.com")
        XCTAssertTrue(Watchlist.matches("api.example.com"))
        XCTAssertTrue(Watchlist.matches("staging.example.com"))
        XCTAssertFalse(Watchlist.matches("example.com.evil.com"))
    }

    func testCaseInsensitive() {
        Watchlist.add("API.Example.COM")
        XCTAssertTrue(Watchlist.matches("api.example.com"))
    }

    func testLoadEmpty() {
        let domains = Watchlist.load()
        XCTAssertTrue(domains.isEmpty)
    }

    func testSubdomainMatch() {
        Watchlist.add("example.com")
        XCTAssertTrue(Watchlist.matches("example.com"))
        XCTAssertTrue(Watchlist.matches("api.example.com"))
    }
}

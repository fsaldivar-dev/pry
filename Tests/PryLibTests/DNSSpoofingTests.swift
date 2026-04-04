import XCTest
@testable import PryLib

final class DNSSpoofingTests: XCTestCase {
    override func setUp() { super.setUp(); DNSSpoofing.clear() }
    override func tearDown() { DNSSpoofing.clear(); super.tearDown() }

    func testAddAndLoad() {
        DNSSpoofing.add(domain: "api.example.com", ip: "127.0.0.1")
        let all = DNSSpoofing.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].domain, "api.example.com")
        XCTAssertEqual(all[0].ip, "127.0.0.1")
    }

    func testResolve() {
        DNSSpoofing.add(domain: "api.example.com", ip: "127.0.0.1")
        XCTAssertEqual(DNSSpoofing.resolve("api.example.com"), "127.0.0.1")
    }

    func testNoResolve() {
        DNSSpoofing.add(domain: "api.example.com", ip: "127.0.0.1")
        XCTAssertNil(DNSSpoofing.resolve("other.com"))
    }

    func testClear() {
        DNSSpoofing.add(domain: "api.example.com", ip: "127.0.0.1")
        DNSSpoofing.clear()
        XCTAssertTrue(DNSSpoofing.loadAll().isEmpty)
    }

    func testCaseInsensitive() {
        DNSSpoofing.add(domain: "api.example.com", ip: "10.0.0.1")
        XCTAssertEqual(DNSSpoofing.resolve("API.EXAMPLE.COM"), "10.0.0.1")
    }

    func testMultipleRules() {
        DNSSpoofing.add(domain: "api.example.com", ip: "127.0.0.1")
        DNSSpoofing.add(domain: "cdn.example.com", ip: "10.0.0.1")
        XCTAssertEqual(DNSSpoofing.resolve("api.example.com"), "127.0.0.1")
        XCTAssertEqual(DNSSpoofing.resolve("cdn.example.com"), "10.0.0.1")
    }
}

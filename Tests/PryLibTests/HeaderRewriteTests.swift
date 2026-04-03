import XCTest
@testable import PryLib

final class HeaderRewriteTests: XCTestCase {
    override func setUp() {
        super.setUp()
        HeaderRewrite.clear()
    }

    override func tearDown() {
        HeaderRewrite.clear()
        super.tearDown()
    }

    func testAddRule() {
        HeaderRewrite.addRule(name: "Authorization", value: "Bearer token123")
        let rules = HeaderRewrite.loadAll()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].action, .add)
        XCTAssertEqual(rules[0].name, "Authorization")
        XCTAssertEqual(rules[0].value, "Bearer token123")
    }

    func testRemoveRule() {
        HeaderRewrite.removeRule(name: "Cookie")
        let rules = HeaderRewrite.loadAll()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].action, .remove)
        XCTAssertEqual(rules[0].name, "Cookie")
    }

    func testApplyAdd() {
        HeaderRewrite.addRule(name: "X-Custom", value: "test123")
        var headers: [(String, String)] = [("Accept", "*/*")]
        headers = HeaderRewrite.apply(to: headers)
        XCTAssertTrue(headers.contains(where: { $0.0 == "X-Custom" && $0.1 == "test123" }))
        XCTAssertTrue(headers.contains(where: { $0.0 == "Accept" }))
    }

    func testApplyRemove() {
        HeaderRewrite.removeRule(name: "Cookie")
        var headers: [(String, String)] = [("Accept", "*/*"), ("Cookie", "session=abc")]
        headers = HeaderRewrite.apply(to: headers)
        XCTAssertFalse(headers.contains(where: { $0.0 == "Cookie" }))
        XCTAssertTrue(headers.contains(where: { $0.0 == "Accept" }))
    }

    func testClear() {
        HeaderRewrite.addRule(name: "X-A", value: "1")
        HeaderRewrite.removeRule(name: "X-B")
        HeaderRewrite.clear()
        XCTAssertTrue(HeaderRewrite.loadAll().isEmpty)
    }
}

import XCTest
@testable import PryLib

final class RuleEngineTests: XCTestCase {
    override func setUp() { super.setUp(); RuleEngine.clear() }
    override func tearDown() { RuleEngine.clear(); super.tearDown() }

    func testParseRuleWithHeaders() {
        let content = """
        rule "/api/*"
          set-header X-Debug "true"
          remove-header Cookie
        """
        let rules = RuleEngine.parse(content: content)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].pattern, "/api/*")
        XCTAssertEqual(rules[0].actions.count, 2)
    }

    func testParseRuleWithStatus() {
        let content = """
        rule "POST /api/auth"
          set-status 200
          set-body '{"token":"mock"}'
        """
        let rules = RuleEngine.parse(content: content)
        XCTAssertEqual(rules.count, 1)
        XCTAssertTrue(rules[0].actions.contains { if case .setStatus(200) = $0 { return true }; return false })
    }

    func testParseRuleWithDelay() {
        let content = """
        rule "/api/slow"
          delay 2000
        """
        let rules = RuleEngine.parse(content: content)
        XCTAssertEqual(rules.count, 1)
        XCTAssertTrue(rules[0].actions.contains { if case .delay(2000) = $0 { return true }; return false })
    }

    func testParseRuleWithDrop() {
        let content = """
        rule "*.tracker.com"
          drop
        """
        let rules = RuleEngine.parse(content: content)
        XCTAssertTrue(rules[0].actions.contains { if case .drop = $0 { return true }; return false })
    }

    func testParseRuleReplaceHost() {
        let content = """
        rule "*.prod.com"
          replace-host staging.com
        """
        let rules = RuleEngine.parse(content: content)
        XCTAssertTrue(rules[0].actions.contains { if case .replaceHost("staging.com") = $0 { return true }; return false })
    }

    func testMatchPattern() {
        let content = """
        rule "/api/*"
          set-header X-Test "1"
        """
        let rules = RuleEngine.parse(content: content)
        RuleEngine.loadRules(rules)
        let matching = RuleEngine.matchingRules(for: "/api/users", method: "GET")
        XCTAssertEqual(matching.count, 1)
    }

    func testNoMatch() {
        let content = """
        rule "/api/*"
          set-header X-Test "1"
        """
        let rules = RuleEngine.parse(content: content)
        RuleEngine.loadRules(rules)
        let matching = RuleEngine.matchingRules(for: "/other/path", method: "GET")
        XCTAssertTrue(matching.isEmpty)
    }

    func testMatchMethodPattern() {
        let content = """
        rule "POST /api/*"
          set-status 200
        """
        let rules = RuleEngine.parse(content: content)
        RuleEngine.loadRules(rules)
        XCTAssertEqual(RuleEngine.matchingRules(for: "/api/auth", method: "POST").count, 1)
        XCTAssertEqual(RuleEngine.matchingRules(for: "/api/auth", method: "GET").count, 0)
    }

    func testApplyRequestRules() {
        let content = """
        rule "/api/*"
          set-header X-Debug "true"
          remove-header Cookie
        """
        let rules = RuleEngine.parse(content: content)
        var headers: [(String, String)] = [("Cookie", "session=abc"), ("Accept", "application/json")]
        let result = RuleEngine.applyRequestRules(rules: rules, headers: &headers)
        XCTAssertFalse(result.shouldDrop)
        XCTAssertTrue(headers.contains { $0.0 == "X-Debug" && $0.1 == "true" })
        XCTAssertFalse(headers.contains { $0.0 == "Cookie" })
    }

    func testMultipleRules() {
        let content = """
        rule "/api/*"
          set-header X-One "1"

        rule "/api/users"
          set-header X-Two "2"
        """
        let rules = RuleEngine.parse(content: content)
        XCTAssertEqual(rules.count, 2)
    }

    func testLoadFromFile() throws {
        let path = "/tmp/pry-test-rules.pry"
        let content = """
        rule "/api/*"
          set-header X-Test "loaded"
        """
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        try RuleEngine.loadFromFile(path: path)
        let matching = RuleEngine.matchingRules(for: "/api/test", method: "GET")
        XCTAssertEqual(matching.count, 1)
        try? FileManager.default.removeItem(atPath: path)
    }
}

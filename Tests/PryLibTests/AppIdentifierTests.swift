import XCTest
@testable import PryLib

final class AppIdentifierTests: XCTestCase {
    func testParseCurl() {
        let app = AppIdentifier.parse(userAgent: "curl/8.7.1")
        XCTAssertEqual(app.icon, "🖥️")
        XCTAssertEqual(app.name, "curl")
        XCTAssertEqual(app.version, "8.7.1")
    }

    func testParseSafariIOS() {
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        let app = AppIdentifier.parse(userAgent: ua)
        XCTAssertEqual(app.icon, "🧭")
        XCTAssertEqual(app.name, "Safari")
    }

    func testParseChrome() {
        let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36"
        let app = AppIdentifier.parse(userAgent: ua)
        XCTAssertEqual(app.icon, "🌐")
        XCTAssertEqual(app.name, "Chrome")
    }

    func testParseiOSApp() {
        let ua = "MyApp/1.0 CFNetwork/1568.100.1 Darwin/24.0.0"
        let app = AppIdentifier.parse(userAgent: ua)
        XCTAssertEqual(app.icon, "📱")
        XCTAssertEqual(app.name, "MyApp")
        XCTAssertEqual(app.version, "1.0")
    }

    func testParsePython() {
        let app = AppIdentifier.parse(userAgent: "python-requests/2.31.0")
        XCTAssertEqual(app.icon, "🐍")
        XCTAssertEqual(app.name, "Python")
    }

    func testParseUnknown() {
        let app = AppIdentifier.parse(userAgent: "SomeWeirdAgent")
        XCTAssertFalse(app.icon.isEmpty)
    }
}

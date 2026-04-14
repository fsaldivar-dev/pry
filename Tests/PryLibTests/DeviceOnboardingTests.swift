import XCTest
@testable import PryLib

final class DeviceOnboardingTests: XCTestCase {

    func testLocalIPAddresses() {
        let ips = DeviceOnboarding.localIPAddresses()
        // On any dev machine, we should find at least one IP
        XCTAssertFalse(ips.isEmpty, "Should detect at least one local IP")
        for ip in ips {
            XCTAssertFalse(ip.contains("127.0.0.1"), "Should not include localhost")
        }
    }

    func testQRPayload() {
        let payload = DeviceOnboarding.generateQRPayload(proxyHost: "192.168.1.50", proxyPort: 8080)
        XCTAssertTrue(payload.contains("192.168.1.50"))
        XCTAssertTrue(payload.contains("8080"))
        // Verify it's valid JSON
        let data = payload.data(using: .utf8)!
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    func testHTMLGeneration() {
        let html = DeviceOnboarding.generateHTML(proxyHost: "192.168.1.50", proxyPort: 8080)
        XCTAssertTrue(html.contains("192.168.1.50"))
        XCTAssertTrue(html.contains("8080"))
        XCTAssertTrue(html.contains("Pry"))
        XCTAssertTrue(html.contains("Configure Proxy"))
        XCTAssertTrue(html.contains("Install Certificate"))
    }

    func testHTMLContainsDeviceInstructions() {
        let html = DeviceOnboarding.generateHTML(proxyHost: "10.0.0.1", proxyPort: 9090)
        XCTAssertTrue(html.contains("iOS"))
        XCTAssertTrue(html.contains("Android"))
        XCTAssertTrue(html.contains("macOS"))
    }
}

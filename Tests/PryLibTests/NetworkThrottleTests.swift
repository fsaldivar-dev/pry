import XCTest
@testable import PryLib

final class NetworkThrottleTests: XCTestCase {
    override func setUp() {
        super.setUp()
        NetworkThrottle.disable()
    }

    override func tearDown() {
        NetworkThrottle.disable()
        super.tearDown()
    }

    func testPreset3G() {
        let config = NetworkThrottle.preset("3g")
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.bytesPerSecond, 750_000)
        XCTAssertEqual(config?.latencyMs, 200)
    }

    func testPresetSlow() {
        let config = NetworkThrottle.preset("slow")
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.bytesPerSecond, 100_000)
        XCTAssertEqual(config?.latencyMs, 500)
    }

    func testPresetEdge() {
        let config = NetworkThrottle.preset("edge")
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.bytesPerSecond, 50_000)
        XCTAssertEqual(config?.latencyMs, 800)
    }

    func testPresetWifi() {
        let config = NetworkThrottle.preset("wifi")
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.bytesPerSecond, 5_000_000)
        XCTAssertEqual(config?.latencyMs, 10)
    }

    func testPresetUnknown() {
        let config = NetworkThrottle.preset("unknown")
        XCTAssertNil(config)
    }

    func testCustomConfig() {
        let config = ThrottleConfig(bytesPerSecond: 256_000, latencyMs: 300)
        NetworkThrottle.enable(config)
        XCTAssertNotNil(NetworkThrottle.current)
        XCTAssertEqual(NetworkThrottle.current?.bytesPerSecond, 256_000)
        XCTAssertEqual(NetworkThrottle.current?.latencyMs, 300)
    }

    func testDisable() {
        NetworkThrottle.enable(ThrottleConfig(bytesPerSecond: 100, latencyMs: 100))
        XCTAssertNotNil(NetworkThrottle.current)
        NetworkThrottle.disable()
        XCTAssertNil(NetworkThrottle.current)
    }

    func testPresetLabel() {
        let config = NetworkThrottle.preset("3g")
        XCTAssertEqual(config?.label, "3G")
    }
}

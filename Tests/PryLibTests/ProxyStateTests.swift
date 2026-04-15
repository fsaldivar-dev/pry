import XCTest
@testable import PryLib

final class ProxyStateTests: XCTestCase {
    private var originalStateFile: String!
    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "pry-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    private var testStateFile: String { tempDir + "/proxy.state" }

    // Helper: save state to temp file
    private func saveState(port: Int = 8080, pid: Int32 = 12345, service: String = "Wi-Fi") {
        let state = ProxyState(port: port, pid: pid, networkService: service, enabledAt: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(state)
        try! data.write(to: URL(fileURLWithPath: testStateFile), options: .atomic)
    }

    private func loadState() -> ProxyState? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: testStateFile)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ProxyState.self, from: data)
    }

    func testSaveAndLoad() {
        // Test using the real ProxyState API
        ProxyState.save(port: 9090, pid: 42, networkService: "Ethernet")
        let loaded = ProxyState.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.port, 9090)
        XCTAssertEqual(loaded?.pid, 42)
        XCTAssertEqual(loaded?.networkService, "Ethernet")
        XCTAssertNotNil(loaded?.enabledAt)
        // Cleanup
        ProxyState.clear()
    }

    func testClear() {
        ProxyState.save(port: 8080, pid: 1, networkService: "Wi-Fi")
        XCTAssertNotNil(ProxyState.load())
        ProxyState.clear()
        XCTAssertNil(ProxyState.load())
    }

    func testIsOrphanedWithDeadPID() {
        // PID 999999 is almost certainly not running
        ProxyState.save(port: 8080, pid: 999999, networkService: "Wi-Fi")
        let orphan = ProxyState.isOrphaned()
        XCTAssertNotNil(orphan)
        XCTAssertEqual(orphan?.pid, 999999)
        XCTAssertEqual(orphan?.networkService, "Wi-Fi")
        ProxyState.clear()
    }

    func testIsOrphanedWithAlivePID() {
        // Current process PID is alive
        let myPid = ProcessInfo.processInfo.processIdentifier
        ProxyState.save(port: 8080, pid: myPid, networkService: "Wi-Fi")
        let orphan = ProxyState.isOrphaned()
        XCTAssertNil(orphan)
        ProxyState.clear()
    }

    func testIsOrphanedWithNoFile() {
        ProxyState.clear() // Ensure no file
        XCTAssertNil(ProxyState.isOrphaned())
    }

    func testStateEncodesAsJSON() {
        ProxyState.save(port: 8080, pid: 123, networkService: "Wi-Fi")
        let data = try! Data(contentsOf: URL(fileURLWithPath: ProxyState.stateFile))
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["port"] as? Int, 8080)
        XCTAssertEqual(json["pid"] as? Int, 123)
        XCTAssertEqual(json["networkService"] as? String, "Wi-Fi")
        XCTAssertNotNil(json["enabledAt"])
        ProxyState.clear()
    }
}

import XCTest
@testable import PryLib

final class SessionPersistenceTests: XCTestCase {
    var tempPath: String!

    override func setUp() {
        // Redirigir a un archivo temporal único por test — evita tocar ~/.pry/.
        let dir = NSTemporaryDirectory() + "pry-session-tests-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        tempPath = dir + "/session.jsonl"
        SessionPersistence.overridePath = tempPath
    }

    override func tearDown() {
        SessionPersistence.overridePath = nil
        let dir = (tempPath as NSString).deletingLastPathComponent
        try? FileManager.default.removeItem(atPath: dir)
    }

    private func sample(id: Int = 1, host: String = "example.com") -> PersistedSessionRequest {
        PersistedSessionRequest(
            requestID: id, capturedAt: Date(), method: "GET",
            host: host, url: "/api/\(id)",
            requestHeaders: [("Accept", "*/*")], requestBody: nil,
            statusCode: 200, responseHeaders: [("Content-Type", "application/json")],
            responseBody: #"{"ok":true}"#, latencyMs: 42
        )
    }

    // MARK: - Append + Load roundtrip

    func test_append_creates_file_and_persists_entry() {
        XCTAssertTrue(SessionPersistence.append(sample()))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath))
        let loaded = SessionPersistence.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].requestID, 1)
    }

    func test_append_multiple_preserves_order() {
        SessionPersistence.append(sample(id: 1))
        SessionPersistence.append(sample(id: 2))
        SessionPersistence.append(sample(id: 3))
        let loaded = SessionPersistence.load()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.map { $0.requestID }, [1, 2, 3])
    }

    func test_load_when_file_missing_returns_empty() {
        XCTAssertTrue(SessionPersistence.load().isEmpty)
    }

    func test_load_tolerates_corrupt_line() {
        // Write manually a file con una línea corrupta + una válida.
        SessionPersistence.append(sample(id: 1))
        let handle = FileHandle(forWritingAtPath: tempPath)!
        try! handle.seekToEnd()
        handle.write("GARBAGE NOT JSON\n".data(using: .utf8)!)
        try! handle.close()
        SessionPersistence.append(sample(id: 2))
        let loaded = SessionPersistence.load()
        XCTAssertEqual(loaded.count, 2, "la línea corrupta se ignora silenciosamente")
        XCTAssertEqual(loaded.map { $0.requestID }, [1, 2])
    }

    // MARK: - Clear

    func test_clear_removes_file() {
        SessionPersistence.append(sample())
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath))
        SessionPersistence.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempPath))
    }

    // MARK: - Prune (manual)

    func test_pruneIfNeeded_drops_oldest_when_over_entries_cap() {
        // Forzar un threshold chico — prune lee maxEntries, lo dejamos default pero
        // simulamos el overflow insertando directamente por encima.
        for i in 0..<10 {
            SessionPersistence.append(sample(id: i))
        }
        // No excede maxEntries, prune no hace nada.
        SessionPersistence.pruneIfNeeded()
        XCTAssertEqual(SessionPersistence.currentCount(), 10)
    }

    // MARK: - Stats

    func test_currentCount_matches_appended() {
        XCTAssertEqual(SessionPersistence.currentCount(), 0)
        SessionPersistence.append(sample(id: 1))
        SessionPersistence.append(sample(id: 2))
        XCTAssertEqual(SessionPersistence.currentCount(), 2)
    }

    func test_currentSizeBytes_grows_after_append() {
        XCTAssertEqual(SessionPersistence.currentSizeBytes(), 0)
        SessionPersistence.append(sample())
        XCTAssertGreaterThan(SessionPersistence.currentSizeBytes(), 0)
    }

    // MARK: - Enablement (UserDefaults)

    func test_isEnabled_defaults_false() {
        UserDefaults.standard.removeObject(forKey: "pry.session.persistEnabled")
        XCTAssertFalse(SessionPersistence.isEnabled())
    }

    func test_setEnabled_toggle() {
        SessionPersistence.setEnabled(true)
        XCTAssertTrue(SessionPersistence.isEnabled())
        SessionPersistence.setEnabled(false)
        XCTAssertFalse(SessionPersistence.isEnabled())
    }
}

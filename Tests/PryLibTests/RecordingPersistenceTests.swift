import XCTest
@testable import PryLib

final class RecordingPersistenceTests: XCTestCase {
    // MARK: - Sanitization

    func test_load_rejectsPathTraversal() {
        XCTAssertNil(RecordingPersistence.load(name: "../../../etc/passwd"))
        XCTAssertNil(RecordingPersistence.load(name: "a/b"))
        XCTAssertNil(RecordingPersistence.load(name: "a\\b"))
        XCTAssertNil(RecordingPersistence.load(name: ".."))
        XCTAssertNil(RecordingPersistence.load(name: "."))
        XCTAssertNil(RecordingPersistence.load(name: ""))
        XCTAssertNil(RecordingPersistence.load(name: "   "))
    }

    func test_save_rejectsInvalidName() {
        let bad = Recording(name: "../../hacked")
        XCTAssertThrowsError(try RecordingPersistence.save(bad))
    }

    func test_delete_noOpOnInvalidName() {
        // No throw, no file affected.
        RecordingPersistence.delete(name: "../etc/passwd")
        RecordingPersistence.delete(name: "")
    }

    // MARK: - Roundtrip

    func test_save_and_load_preservesData() throws {
        let name = "roundtrip-\(UUID().uuidString)"
        var recording = Recording(name: name)
        recording.steps.append(RecordingStep(
            sequence: 1, timestamp: Date(), method: "GET",
            url: "/api/users", host: "example.com",
            requestHeaders: [CodableHeader(name: "Accept", value: "*/*")],
            requestBody: nil, statusCode: 200,
            responseHeaders: [CodableHeader(name: "Content-Type", value: "application/json")],
            responseBody: #"{"ok":true}"#, latencyMs: 42
        ))
        recording.stoppedAt = Date()
        try RecordingPersistence.save(recording)

        defer { RecordingPersistence.delete(name: name) }

        let loaded = RecordingPersistence.load(name: name)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, name)
        XCTAssertEqual(loaded?.steps.count, 1)
        XCTAssertEqual(loaded?.steps[0].method, "GET")
        XCTAssertEqual(loaded?.steps[0].statusCode, 200)
    }

    func test_list_includesSavedRecording() throws {
        let name = "listed-\(UUID().uuidString)"
        let recording = Recording(name: name)
        try RecordingPersistence.save(recording)
        defer { RecordingPersistence.delete(name: name) }

        XCTAssertTrue(RecordingPersistence.list().contains(name))
    }

    func test_delete_removesFile() throws {
        let name = "deleteme-\(UUID().uuidString)"
        let recording = Recording(name: name)
        try RecordingPersistence.save(recording)
        XCTAssertNotNil(RecordingPersistence.load(name: name))
        RecordingPersistence.delete(name: name)
        XCTAssertNil(RecordingPersistence.load(name: name))
    }
}

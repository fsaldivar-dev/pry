import XCTest
@testable import PryLib

final class RecorderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Recorder.clearAll()
        MockEngine.shared.clearAll()
        _ = Recorder.shared.stop() // Ensure not recording
    }

    override func tearDown() {
        _ = Recorder.shared.stop()
        Recorder.clearAll()
        MockEngine.shared.clearAll()
        Config.clearMocks()
        super.tearDown()
    }

    func testStartAndStop() {
        XCTAssertFalse(Recorder.shared.isRecording)
        Recorder.shared.start(name: "test")
        XCTAssertTrue(Recorder.shared.isRecording)
        let recording = Recorder.shared.stop()
        XCTAssertFalse(Recorder.shared.isRecording)
        XCTAssertNotNil(recording)
        XCTAssertEqual(recording?.name, "test")
        XCTAssertNotNil(recording?.stoppedAt)
    }

    func testCaptureSteps() {
        Recorder.shared.start(name: "capture-test")

        Recorder.shared.noteRequestStart(requestId: 1, method: "GET", url: "/api/users",
                                          host: "example.com", headers: [("Accept", "application/json")], body: nil)
        Recorder.shared.noteResponseComplete(requestId: 1, statusCode: 200,
                                              headers: [("Content-Type", "application/json")], body: "{\"users\":[]}")

        Recorder.shared.noteRequestStart(requestId: 2, method: "POST", url: "/api/login",
                                          host: "example.com", headers: [], body: "{\"user\":\"test\"}")
        Recorder.shared.noteResponseComplete(requestId: 2, statusCode: 200,
                                              headers: [], body: "{\"token\":\"abc\"}")

        let recording = Recorder.shared.stop()!
        XCTAssertEqual(recording.steps.count, 2)
        XCTAssertEqual(recording.steps[0].sequence, 1)
        XCTAssertEqual(recording.steps[0].method, "GET")
        XCTAssertEqual(recording.steps[0].url, "/api/users")
        XCTAssertEqual(recording.steps[1].sequence, 2)
        XCTAssertEqual(recording.steps[1].method, "POST")
    }

    func testSaveAndLoad() {
        Recorder.shared.start(name: "persist-test")
        Recorder.shared.noteRequestStart(requestId: 1, method: "GET", url: "/test",
                                          host: "example.com", headers: [], body: nil)
        Recorder.shared.noteResponseComplete(requestId: 1, statusCode: 200, headers: [], body: "{}")
        _ = Recorder.shared.stop()

        let loaded = Recorder.load(name: "persist-test")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "persist-test")
        XCTAssertEqual(loaded?.steps.count, 1)
    }

    func testList() {
        Recorder.shared.start(name: "alpha")
        _ = Recorder.shared.stop()
        Recorder.shared.start(name: "beta")
        _ = Recorder.shared.stop()

        let names = Recorder.list()
        XCTAssertEqual(names, ["alpha", "beta"])
    }

    func testDelete() {
        Recorder.shared.start(name: "to-delete")
        _ = Recorder.shared.stop()
        XCTAssertNotNil(Recorder.load(name: "to-delete"))
        Recorder.delete(name: "to-delete")
        XCTAssertNil(Recorder.load(name: "to-delete"))
    }

    func testToMocks() {
        Recorder.shared.start(name: "mock-convert")
        Recorder.shared.noteRequestStart(requestId: 1, method: "GET", url: "/api/data",
                                          host: "example.com", headers: [], body: nil)
        Recorder.shared.noteResponseComplete(requestId: 1, statusCode: 200, headers: [], body: "{\"data\":true}")
        _ = Recorder.shared.stop()

        let count = Recorder.toMocks(name: "mock-convert")
        XCTAssertEqual(count, 1)
        let mocks = MockEngine.shared.looseMockList()
        XCTAssertEqual(mocks.count, 1)
        XCTAssertEqual(mocks.first?.pattern, "/api/data")
        XCTAssertEqual(mocks.first?.body, "{\"data\":true}")
    }

    func testIgnoreStepsWhenNotRecording() {
        Recorder.shared.noteRequestStart(requestId: 1, method: "GET", url: "/test",
                                          host: "example.com", headers: [], body: nil)
        Recorder.shared.noteResponseComplete(requestId: 1, statusCode: 200, headers: [], body: "{}")
        // Should not crash, just no-op
    }
}

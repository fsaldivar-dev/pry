import XCTest
@testable import PryApp
import PryLib

@available(macOS 14, *)
final class RecordingsStoreTests: XCTestCase {
    var store: RecordingsStore!
    var bus: EventBus!

    @MainActor
    override func setUp() async throws {
        // Importante: estos tests usan el singleton legacy Recorder.shared bajo el hood.
        // Para evitar leak entre tests, paramos cualquier grabación activa al empezar.
        _ = Recorder.shared.stop()
        bus = EventBus()
        store = RecordingsStore(bus: bus)
    }

    @MainActor
    override func tearDown() async throws {
        _ = store.stop() // garantiza clean state
    }

    @MainActor
    func test_initialState_notRecording() {
        XCTAssertFalse(store.isRecording)
        XCTAssertNil(store.currentRecordingName)
    }

    @MainActor
    func test_start_togglesIsRecording() {
        store.start(name: "test-recording-\(UUID().uuidString)")
        XCTAssertTrue(store.isRecording)
    }

    @MainActor
    func test_start_setsCurrentRecordingName() {
        let name = "test-rec-\(UUID().uuidString)"
        store.start(name: name)
        XCTAssertEqual(store.currentRecordingName, name)
    }

    @MainActor
    func test_start_trimsWhitespace() {
        let raw = "  named  "
        store.start(name: raw)
        XCTAssertEqual(store.currentRecordingName, "named")
    }

    @MainActor
    func test_start_ignoresEmpty() {
        store.start(name: "   ")
        XCTAssertFalse(store.isRecording)
        XCTAssertNil(store.currentRecordingName)
    }

    @MainActor
    func test_stop_clearsRecordingState() {
        store.start(name: "test-rec-\(UUID().uuidString)")
        _ = store.stop()
        XCTAssertFalse(store.isRecording)
        XCTAssertNil(store.currentRecordingName)
    }

    @MainActor
    func test_stop_returnsSavedRecording() {
        let name = "test-rec-\(UUID().uuidString)"
        store.start(name: name)
        let result = store.stop()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, name)
    }

    @MainActor
    func test_stop_withoutStart_returnsNil() {
        let result = store.stop()
        XCTAssertNil(result)
    }

    @MainActor
    func test_reload_mirrorsLegacyState() {
        store.start(name: "test-reload-\(UUID().uuidString)")
        // Crear nueva store — debería ver el estado legacy vigente.
        let other = RecordingsStore(bus: bus)
        XCTAssertTrue(other.isRecording, "nueva store lee estado actual de Recorder.shared")
    }

    @MainActor
    func test_delete_removesRecording() {
        let name = "test-del-\(UUID().uuidString)"
        store.start(name: name)
        _ = store.stop()
        XCTAssertTrue(store.recordings.contains(name))
        store.delete(name: name)
        XCTAssertFalse(store.recordings.contains(name))
    }
}

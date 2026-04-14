import Foundation
import Observation
import PryLib

/// @Observable bridge over Recorder for SwiftUI.
@available(macOS 14, *)
@Observable
@MainActor
public final class RecorderUIManager {
    public var isRecording: Bool = false
    public var recordings: [String] = []

    public init() { reload() }

    public func reload() {
        isRecording = Recorder.shared.isRecording
        recordings = Recorder.list()
    }

    public var lastRecordingName: String?

    public func start(name: String, domains: [String] = []) {
        Recorder.shared.start(name: name, domains: domains)
        isRecording = true
        lastRecordingName = name
    }

    public func stop() -> Recording? {
        let recording = Recorder.shared.stop()
        isRecording = false
        lastRecordingName = nil
        reload()
        return recording
    }

    public func delete(name: String) {
        Recorder.delete(name: name)
        reload()
    }

    public func toMocks(name: String) -> Int {
        let count = Recorder.toMocks(name: name)
        return count
    }

    public func load(name: String) -> Recording? {
        Recorder.load(name: name)
    }
}

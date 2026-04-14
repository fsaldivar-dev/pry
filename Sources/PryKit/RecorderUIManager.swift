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

    public func start(name: String) {
        Recorder.shared.start(name: name)
        isRecording = true
    }

    public func stop() {
        _ = Recorder.shared.stop()
        isRecording = false
        reload()
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

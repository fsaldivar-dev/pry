import Foundation
import Observation
import PryLib

/// @Observable bridge over BreakpointStore and RequestBreakpointManager for SwiftUI.
@available(macOS 14, *)
@Observable
@MainActor
public final class BreakpointUIManager {
    public var patterns: [String] = []
    public var pausedRequests: [PausedRequest] = []

    public init() {
        patterns = BreakpointStore.shared.all()

        RequestBreakpointManager.shared.onPause = { [weak self] in
            guard let self else { return }
            let paused = RequestBreakpointManager.shared.getPaused()
            Task { @MainActor in
                self.pausedRequests = paused
            }
        }
    }

    public func add(_ pattern: String) {
        BreakpointStore.shared.add(pattern)
        patterns = BreakpointStore.shared.all()
    }

    public func remove(_ pattern: String) {
        BreakpointStore.shared.remove(pattern)
        patterns = BreakpointStore.shared.all()
    }

    public func clearAll() {
        BreakpointStore.shared.clearAll()
        patterns = []
    }

    public func resume(id: Int, action: BreakpointAction) {
        RequestBreakpointManager.shared.resume(id: id, action: action)
        pausedRequests = RequestBreakpointManager.shared.getPaused()
    }

    public func resumeAll() {
        RequestBreakpointManager.shared.resumeAll()
        pausedRequests = []
    }
}

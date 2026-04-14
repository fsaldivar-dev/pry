import Foundation
import Observation
import PryLib

/// @Observable bridge over StatusOverrideStore for SwiftUI.
@available(macOS 14, *)
@Observable
@MainActor
public final class StatusOverrideUIManager {
    public var overrides: [(pattern: String, status: UInt)] = []

    public init() { reload() }

    public func reload() {
        let loaded = StatusOverrideStore.loadAll()
        overrides = loaded.map { ($0.pattern, $0.status) }
    }

    public func save(pattern: String, status: UInt) {
        StatusOverrideStore.save(pattern: pattern, status: status)
        reload()
    }

    public func remove(pattern: String) {
        StatusOverrideStore.remove(pattern: pattern)
        reload()
    }

    public func clearAll() {
        StatusOverrideStore.clear()
        overrides = []
    }
}

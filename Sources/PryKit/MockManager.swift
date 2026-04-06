import Foundation
import Observation
import PryLib

/// @Observable bridge over Config mock CRUD for SwiftUI.
@available(macOS 14, *)
@Observable
@MainActor
public final class MockManager {
    public var mocks: [String: String] = [:]

    public init() {
        reload()
    }

    public func save(path: String, response: String) {
        Config.saveMock(path: path, response: response)
        reload()
    }

    public func reload() {
        mocks = Config.loadMocks()
    }

    public func remove(path: String) {
        Config.removeMock(path: path)
        reload()
    }

    public func clearAll() {
        Config.clearMocks()
        mocks = [:]
    }
}

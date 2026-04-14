import Foundation
import Observation
import PryLib

/// @Observable bridge over MockProject CRUD for SwiftUI.
@available(macOS 14, *)
@Observable
@MainActor
public final class MockProjectUIManager {
    public var mocks: [ProjectMock] = []

    public init() { reload() }

    public func reload() {
        mocks = MockProject.loadAll()
    }

    public func save(_ mock: ProjectMock) throws {
        try MockProject.save(mock)
        reload()
    }

    public func remove(pattern: String) {
        MockProject.remove(pattern: pattern)
        reload()
    }

    public func clearAll() {
        MockProject.clear()
        mocks = []
    }

    public func applyAll() {
        MockProject.applyAll()
    }

    public func initProject() throws {
        try MockProject.initProject()
    }
}

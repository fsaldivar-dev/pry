import Foundation
import Observation
import PryLib

/// @Observable bridge over ScenarioManager CRUD for SwiftUI.
@available(macOS 14, *)
@Observable
@MainActor
public final class ScenarioUIManager {
    public var scenarios: [String] = []
    public var activeScenario: String?

    public init() { reload() }

    public func reload() {
        scenarios = ScenarioManager.list()
        activeScenario = ScenarioManager.active()
    }

    public func activate(name: String) {
        _ = ScenarioManager.activate(name: name)
        reload()
    }

    public func deactivate() {
        ScenarioManager.deactivate()
        reload()
    }

    public func create(name: String) throws {
        try ScenarioManager.create(name: name)
        reload()
    }

    public func delete(name: String) {
        ScenarioManager.delete(name: name)
        reload()
    }

    public func capture(name: String) throws {
        try ScenarioManager.capture(name: name)
        reload()
    }

    public func load(name: String) -> Scenario? {
        ScenarioManager.load(name: name)
    }

    public func exportScenario(name: String, to path: String) throws {
        try ScenarioExporter.export(name: name, to: path)
    }

    public func importScenario(from path: String) throws -> String {
        let name = try ScenarioExporter.importScenario(from: path)
        reload()
        return name
    }
}

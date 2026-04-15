import Foundation

/// Wraps a Scenario with export metadata for sharing.
public struct ExportedScenario: Codable {
    public let scenario: Scenario
    public let exportedAt: Date
    public let pryVersion: String

    public init(scenario: Scenario, pryVersion: String = "1.0.0") {
        self.scenario = scenario
        self.exportedAt = Date()
        self.pryVersion = pryVersion
    }
}

/// Exports and imports scenarios as .pryscenario files for team sharing.
public struct ScenarioExporter {

    /// Export a scenario to a .pryscenario file.
    public static func export(name: String, to path: String) throws {
        guard let scenario = ScenarioManager.load(name: name) else {
            throw ScenarioExportError.scenarioNotFound(name)
        }
        let exported = ExportedScenario(scenario: scenario)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(exported)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// Import a scenario from a .pryscenario file.
    /// Returns the scenario name. If a scenario with the same name exists, appends "-imported".
    @discardableResult
    public static func importScenario(from path: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode(ExportedScenario.self, from: data)

        var scenario = exported.scenario

        // Handle name conflicts
        let existingNames = Set(ScenarioManager.list())
        if existingNames.contains(scenario.name) {
            var candidate = scenario.name + "-imported"
            var counter = 1
            while existingNames.contains(candidate) {
                counter += 1
                candidate = scenario.name + "-imported-\(counter)"
            }
            scenario.name = candidate
        }

        try ScenarioManager.save(scenario)
        return scenario.name
    }
}

public enum ScenarioExportError: Error, CustomStringConvertible {
    case scenarioNotFound(String)

    public var description: String {
        switch self {
        case .scenarioNotFound(let name):
            return "Scenario '\(name)' not found"
        }
    }
}

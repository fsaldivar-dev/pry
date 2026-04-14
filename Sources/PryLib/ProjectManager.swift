import Foundation

public struct Project: Codable, Equatable {
    public var name: String
    public let createdAt: Date

    public init(name: String) {
        self.name = name
        self.createdAt = Date()
    }
}

/// Manages the Project > Scenario hierarchy.
/// Storage layout:
/// ```
/// .pry/projects/{project-name}/
///   ├── project.json
///   ├── scenarios/
///   │    └── {scenario}.json
///   └── recordings/
///        └── {recording}.json
/// ```
public struct ProjectManager {

    private static let projectsDir = ".pry/projects"
    private static let activeFile = ".pry/active-project"

    // MARK: - Project CRUD

    public static func create(name: String) throws {
        let dir = "\(projectsDir)/\(name)"
        try FileManager.default.createDirectory(atPath: "\(dir)/scenarios", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(dir)/recordings", withIntermediateDirectories: true)
        let project = Project(name: name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        try data.write(to: URL(fileURLWithPath: "\(dir)/project.json"), options: .atomic)
    }

    public static func list() -> [String] {
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: projectsDir) else { return [] }
        return dirs.filter {
            FileManager.default.fileExists(atPath: "\(projectsDir)/\($0)/project.json")
        }.sorted()
    }

    public static func delete(name: String) {
        if activeProject() == name { deactivate() }
        let dir = "\(projectsDir)/\(name)"
        try? FileManager.default.removeItem(atPath: dir)
    }

    public static func load(name: String) -> Project? {
        let path = "\(projectsDir)/\(name)/project.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Project.self, from: data)
    }

    // MARK: - Scenario CRUD within Project

    public static func scenariosDir(project: String) -> String {
        "\(projectsDir)/\(project)/scenarios"
    }

    public static func listScenarios(project: String) -> [String] {
        let dir = scenariosDir(project: project)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return files.filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
            .sorted()
    }

    public static func loadScenario(project: String, scenario: String) -> Scenario? {
        let path = "\(scenariosDir(project: project))/\(scenario).json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(Scenario.self, from: data)
    }

    public static func saveScenario(_ scenario: Scenario, project: String) throws {
        let dir = scenariosDir(project: project)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(scenario)
        try data.write(to: URL(fileURLWithPath: "\(dir)/\(scenario.name).json"), options: .atomic)
    }

    public static func deleteScenario(project: String, scenario: String) {
        if activeScenario() == scenario && activeProject() == project {
            deactivate()
        }
        let path = "\(scenariosDir(project: project))/\(scenario).json"
        try? FileManager.default.removeItem(atPath: path)
    }

    public static func createScenario(project: String, name: String) throws {
        let scenario = Scenario(name: name)
        try saveScenario(scenario, project: project)
    }

    /// Copy mocks from one scenario to another (one-time copy, no live reference).
    public static func copyMocks(fromProject: String, fromScenario: String,
                                  toProject: String, toScenario: String) -> Int {
        guard let source = loadScenario(project: fromProject, scenario: fromScenario),
              var dest = loadScenario(project: toProject, scenario: toScenario) else { return 0 }
        let copied = source.mocks
        dest.mocks.append(contentsOf: copied)
        try? saveScenario(dest, project: toProject)
        return copied.count
    }

    // MARK: - Activation

    /// Activate a project's scenario.
    public static func activate(project: String, scenario: String) -> Bool {
        guard let scenarioData = loadScenario(project: project, scenario: scenario) else { return false }

        // Clear existing config via ScenarioManager
        ScenarioManager.deactivate()

        // Apply all config from scenario
        for domain in scenarioData.watchlist { Watchlist.add(domain) }
        MockEngine.shared.loadScenarioMocks(scenarioData.mocks)
        for header in scenarioData.headers {
            if header.action == "add", let value = header.value {
                HeaderRewrite.addRule(name: header.name, value: value)
            } else if header.action == "remove" {
                HeaderRewrite.removeRule(name: header.name)
            }
        }
        for map in scenarioData.mapLocal { MapLocal.save(regex: map.regex, filePath: map.filePath) }
        for redirect in scenarioData.mapRemote { MapRemote.save(sourceHost: redirect.source, targetHost: redirect.target) }
        for dns in scenarioData.dns { DNSSpoofing.add(domain: dns.domain, ip: dns.ip) }
        for pattern in scenarioData.breakpoints { BreakpointStore.shared.add(pattern) }
        for domain in scenarioData.blocklist { BlockList.add(domain) }
        if !scenarioData.rules.isEmpty {
            let parsed = RuleEngine.parse(content: scenarioData.rules)
            RuleEngine.loadRules(parsed)
        }

        // Save active state
        let activeState = "\(project)/\(scenario)"
        try? activeState.write(toFile: activeFile, atomically: true, encoding: .utf8)

        return true
    }

    public static func deactivate() {
        ScenarioManager.deactivate()
        try? FileManager.default.removeItem(atPath: activeFile)
    }

    public static func activeProject() -> String? {
        guard let content = try? String(contentsOfFile: activeFile, encoding: .utf8) else { return nil }
        let parts = content.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/", maxSplits: 1)
        return parts.count >= 1 ? String(parts[0]) : nil
    }

    public static func activeScenario() -> String? {
        guard let content = try? String(contentsOfFile: activeFile, encoding: .utf8) else { return nil }
        let parts = content.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/", maxSplits: 1)
        return parts.count >= 2 ? String(parts[1]) : nil
    }

    /// Capture current proxy state as a scenario within a project.
    public static func captureScenario(project: String, name: String) throws {
        try ScenarioManager.capture(name: name)
        // Move from legacy location to project
        if let scenario = ScenarioManager.load(name: name) {
            try saveScenario(scenario, project: project)
            ScenarioManager.delete(name: name)
        }
    }
}

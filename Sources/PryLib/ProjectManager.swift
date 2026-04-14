import Foundation

public enum TrackingMode: String, Codable, CaseIterable, Sendable {
    case domain = "domain"
    case userAgent = "userAgent"
    case both = "both"
}

public struct TrackingConfig: Codable, Equatable, Sendable {
    public var domains: [String]
    public var userAgents: [String]  // supports glob patterns like "SimulationPry/*"
    public var mode: TrackingMode
    public var autoDetect: Bool

    public init(domains: [String] = [], userAgents: [String] = [],
                mode: TrackingMode = .domain, autoDetect: Bool = true) {
        self.domains = domains
        self.userAgents = userAgents
        self.mode = mode
        self.autoDetect = autoDetect
    }

    /// Check if a request matches this tracking config.
    public func matches(host: String, userAgent: String?) -> Bool {
        switch mode {
        case .domain:
            return matchesDomain(host)
        case .userAgent:
            return matchesUserAgent(userAgent)
        case .both:
            return matchesDomain(host) && matchesUserAgent(userAgent)
        }
    }

    private func matchesDomain(_ host: String) -> Bool {
        guard !domains.isEmpty else { return false }
        let h = host.lowercased()
        return domains.contains { domain in
            let d = domain.lowercased()
            if d.hasPrefix("*.") {
                return h.hasSuffix(String(d.dropFirst(1))) || h == String(d.dropFirst(2))
            }
            return h == d || h.hasSuffix(".\(d)")
        }
    }

    private func matchesUserAgent(_ ua: String?) -> Bool {
        guard let ua = ua, !userAgents.isEmpty else { return userAgents.isEmpty }
        return userAgents.contains { pattern in
            if pattern.contains("*") {
                let regex = "^" + NSRegularExpression.escapedPattern(for: pattern)
                    .replacingOccurrences(of: "\\*", with: ".*") + "$"
                return (try? NSRegularExpression(pattern: regex))
                    .flatMap { $0.firstMatch(in: ua, range: NSRange(ua.startIndex..., in: ua)) } != nil
            }
            return ua.contains(pattern)
        }
    }
}

public struct Project: Codable, Equatable {
    public var name: String
    public let createdAt: Date
    public var tracking: TrackingConfig

    enum CodingKeys: String, CodingKey {
        case name, createdAt, tracking
    }

    public init(name: String) {
        self.name = name
        self.createdAt = Date()
        self.tracking = TrackingConfig()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        tracking = try c.decodeIfPresent(TrackingConfig.self, forKey: .tracking) ?? TrackingConfig()
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

        // Apply watchlist from scenario + project tracking domains
        for domain in scenarioData.watchlist { Watchlist.add(domain) }
        // Also add project tracking domains to watchlist for HTTPS interception
        if let proj = load(name: project) {
            for domain in proj.tracking.domains {
                Watchlist.add(domain)
            }
        }
        MockEngine.shared.loadScenarioMocks(scenarioData.mocks)
        print("[ProjectManager] Activated \(project)/\(scenario) with \(scenarioData.mocks.count) mocks, MockEngine now has \(MockEngine.shared.count) total")
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

    // MARK: - Tracking

    /// Update tracking config for a project.
    public static func updateTracking(project: String, config: TrackingConfig) {
        guard var proj = load(name: project) else { return }
        proj.tracking = config
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(proj) {
            try? data.write(to: URL(fileURLWithPath: "\(projectsDir)/\(project)/project.json"), options: .atomic)
        }
    }

    /// Auto-detect: add a user-agent to a project's tracking if autoDetect is on.
    public static func autoLearnUserAgent(project: String, userAgent: String) {
        guard var proj = load(name: project), proj.tracking.autoDetect else { return }
        let ua = userAgent.trimmingCharacters(in: .whitespaces)
        if !ua.isEmpty && !proj.tracking.userAgents.contains(ua) {
            proj.tracking.userAgents.append(ua)
            updateTracking(project: project, config: proj.tracking)
        }
    }

    /// Find which project a request belongs to.
    public static func findProject(host: String, userAgent: String?) -> String? {
        for project in list() {
            guard let proj = load(name: project) else { continue }
            if proj.tracking.matches(host: host, userAgent: userAgent) {
                return project
            }
        }
        return nil
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

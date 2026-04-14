import Foundation

// MARK: - Scenario Data Model

/// Entry types for scenario configuration
public struct MockEntry: Codable, Equatable {
    public let path: String
    public let method: String?
    public let status: UInt
    public let body: String

    public init(path: String, method: String? = nil, status: UInt = 200, body: String) {
        self.path = path; self.method = method; self.status = status; self.body = body
    }
}

public struct HeaderEntry: Codable, Equatable {
    public let action: String  // "add" or "remove"
    public let name: String
    public let value: String?

    public init(action: String, name: String, value: String? = nil) {
        self.action = action; self.name = name; self.value = value
    }
}

public struct MapLocalEntry: Codable, Equatable {
    public let regex: String
    public let filePath: String

    public init(regex: String, filePath: String) {
        self.regex = regex; self.filePath = filePath
    }
}

public struct MapRemoteEntry: Codable, Equatable {
    public let source: String
    public let target: String

    public init(source: String, target: String) {
        self.source = source; self.target = target
    }
}

public struct DNSEntry: Codable, Equatable {
    public let domain: String
    public let ip: String

    public init(domain: String, ip: String) {
        self.domain = domain; self.ip = ip
    }
}

public struct StatusOverrideEntry: Codable, Equatable {
    public let pattern: String
    public let status: UInt

    public init(pattern: String, status: UInt) {
        self.pattern = pattern; self.status = status
    }
}

/// A Scenario bundles all proxy configuration into a single activatable unit.
public struct Scenario: Codable, Equatable {
    public var name: String
    public var watchlist: [String]
    public var mocks: [MockEntry]
    public var headers: [HeaderEntry]
    public var mapLocal: [MapLocalEntry]
    public var mapRemote: [MapRemoteEntry]
    public var dns: [DNSEntry]
    public var breakpoints: [String]
    public var blocklist: [String]
    public var statusOverrides: [StatusOverrideEntry]
    public var rules: String

    public init(name: String) {
        self.name = name
        self.watchlist = []
        self.mocks = []
        self.headers = []
        self.mapLocal = []
        self.mapRemote = []
        self.dns = []
        self.breakpoints = []
        self.blocklist = []
        self.statusOverrides = []
        self.rules = ""
    }
}

// MARK: - ScenarioManager

/// Manages scenario CRUD and activation. Scenarios are stored as JSON in .pry/scenarios/.
public struct ScenarioManager {

    private static let scenariosDir = ".pry/scenarios"
    private static let activeFile = ".pry/active-scenario"

    // MARK: - CRUD

    /// Create a new empty scenario.
    public static func create(name: String) throws {
        let scenario = Scenario(name: name)
        try save(scenario)
    }

    /// Save a scenario to disk.
    public static func save(_ scenario: Scenario) throws {
        let dir = scenariosDir
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(scenario)
        let path = "\(dir)/\(scenario.name).json"
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// Load a scenario by name.
    public static func load(name: String) -> Scenario? {
        let path = "\(scenariosDir)/\(name).json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(Scenario.self, from: data)
    }

    /// List all available scenario names.
    public static func list() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: scenariosDir) else { return [] }
        return files.filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
            .sorted()
    }

    /// Delete a scenario. Deactivates first if it's the active one.
    public static func delete(name: String) {
        if active() == name { deactivate() }
        let path = "\(scenariosDir)/\(name).json"
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Activation

    /// Get the currently active scenario name, or nil.
    public static func active() -> String? {
        guard let name = try? String(contentsOfFile: activeFile, encoding: .utf8) else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Activate a scenario — clears all current config, then applies the scenario's config.
    public static func activate(name: String) -> Bool {
        guard let scenario = load(name: name) else { return false }

        // Clear all existing config
        clearAllConfig()

        // Apply watchlist
        for domain in scenario.watchlist {
            Watchlist.add(domain)
        }

        // Apply mocks
        for mock in scenario.mocks {
            Config.saveMock(path: mock.path, response: mock.body)
        }

        // Apply headers
        for header in scenario.headers {
            if header.action == "add", let value = header.value {
                HeaderRewrite.addRule(name: header.name, value: value)
            } else if header.action == "remove" {
                HeaderRewrite.removeRule(name: header.name)
            }
        }

        // Apply map local
        for map in scenario.mapLocal {
            MapLocal.save(regex: map.regex, filePath: map.filePath)
        }

        // Apply map remote
        for redirect in scenario.mapRemote {
            MapRemote.save(sourceHost: redirect.source, targetHost: redirect.target)
        }

        // Apply DNS overrides
        for dns in scenario.dns {
            DNSSpoofing.add(domain: dns.domain, ip: dns.ip)
        }

        // Apply breakpoints
        for pattern in scenario.breakpoints {
            BreakpointStore.shared.add(pattern)
        }

        // Apply blocklist
        for domain in scenario.blocklist {
            BlockList.add(domain)
        }

        // Apply status overrides
        for override in scenario.statusOverrides {
            StatusOverrideStore.save(pattern: override.pattern, status: override.status)
        }

        // Apply rules
        if !scenario.rules.isEmpty {
            let parsed = RuleEngine.parse(content: scenario.rules)
            RuleEngine.loadRules(parsed)
        }

        // Mark as active
        try? name.write(toFile: activeFile, atomically: true, encoding: .utf8)

        return true
    }

    /// Deactivate the current scenario — clears all config.
    public static func deactivate() {
        clearAllConfig()
        try? FileManager.default.removeItem(atPath: activeFile)
    }

    /// Capture current proxy state as a new scenario.
    public static func capture(name: String) throws {
        var scenario = Scenario(name: name)

        // Capture watchlist
        scenario.watchlist = Watchlist.load().sorted()

        // Capture mocks
        let mocks = Config.loadMocks()
        scenario.mocks = mocks.map { MockEntry(path: $0.key, body: $0.value) }

        // Capture headers — map HeaderRewrite.Action enum to string
        let headers = HeaderRewrite.loadAll()
        scenario.headers = headers.map {
            HeaderEntry(
                action: $0.action == .add ? "add" : "remove",
                name: $0.name,
                value: $0.value
            )
        }

        // Capture map local
        let maps = MapLocal.loadAll()
        scenario.mapLocal = maps.map { MapLocalEntry(regex: $0.regex, filePath: $0.filePath) }

        // Capture map remote
        let redirects = MapRemote.loadAll()
        scenario.mapRemote = redirects.map { MapRemoteEntry(source: $0.sourceHost, target: $0.targetHost) }

        // Capture DNS
        let dns = DNSSpoofing.loadAll()
        scenario.dns = dns.map { DNSEntry(domain: $0.domain, ip: $0.ip) }

        // Capture breakpoints
        scenario.breakpoints = BreakpointStore.shared.all()

        // Capture blocklist
        scenario.blocklist = BlockList.loadAll()

        // Capture status overrides
        let overrides = StatusOverrideStore.loadAll()
        scenario.statusOverrides = overrides.map { StatusOverrideEntry(pattern: $0.pattern, status: $0.status) }

        try save(scenario)
    }

    // MARK: - Private

    private static func clearAllConfig() {
        Config.clearMocks()
        HeaderRewrite.clear()
        MapLocal.clear()
        MapRemote.clear()
        DNSSpoofing.clear()
        BreakpointStore.shared.clearAll()
        BlockList.clear()
        StatusOverrideStore.clear()
        RuleEngine.clear()
        // Watchlist has no clear() — remove each domain individually
        let domains = Watchlist.load()
        for domain in domains {
            Watchlist.remove(domain)
        }
    }
}

import Foundation

/// A project mock stored as an individual JSON file in .pry/mocking/.
public struct ProjectMock: Codable, Equatable {
    public let id: String
    public let method: String?
    public let pattern: String
    public let status: UInt
    public let headers: [String: String]?
    public let body: String
    public let delay: Int?  // milliseconds
    public let notes: String?

    public init(pattern: String, body: String, method: String? = nil, status: UInt = 200,
                headers: [String: String]? = nil, delay: Int? = nil, notes: String? = nil) {
        // Generate ID from pattern: /api/login → api-login
        self.id = pattern.replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
        self.method = method
        self.pattern = pattern
        self.status = status
        self.headers = headers
        self.body = body
        self.delay = delay
        self.notes = notes
    }

    /// Convert to UnifiedMock for use with MockEngine.
    public func toUnifiedMock() -> UnifiedMock {
        UnifiedMock(
            id: id,
            method: method,
            pattern: pattern,
            status: status,
            headers: headers,
            body: body,
            delay: delay,
            notes: notes,
            source: .loose,
            isEnabled: true
        )
    }
}

/// Manages organized mock files in .pry/mocking/ directory.
/// Coexists with loose mocks (pry mock). Project mocks are persistent and versionable.
public struct MockProject {

    private static var mockingDir: String {
        StoragePaths.ensureRoot()
        return StoragePaths.mockingDir
    }

    /// Initialize the mocking project directory.
    public static func initProject() throws {
        try FileManager.default.createDirectory(atPath: mockingDir, withIntermediateDirectories: true)
    }

    /// Save a mock to the project.
    public static func save(_ mock: ProjectMock) throws {
        try initProject()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(mock)
        let path = "\(mockingDir)/\(mock.id).json"
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// Load all project mocks.
    public static func loadAll() -> [ProjectMock] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: mockingDir) else { return [] }
        return files.filter { $0.hasSuffix(".json") }.compactMap { filename in
            let path = "\(mockingDir)/\(filename)"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
            return try? JSONDecoder().decode(ProjectMock.self, from: data)
        }.sorted { $0.pattern < $1.pattern }
    }

    /// Load a specific mock by ID.
    public static func load(id: String) -> ProjectMock? {
        let path = "\(mockingDir)/\(id).json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(ProjectMock.self, from: data)
    }

    /// Remove a mock by pattern.
    public static func remove(pattern: String) {
        let mocks = loadAll()
        for mock in mocks where mock.pattern == pattern {
            let path = "\(mockingDir)/\(mock.id).json"
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    /// Clear all project mocks.
    public static func clear() {
        try? FileManager.default.removeItem(atPath: mockingDir)
    }

    /// Apply all project mocks to MockEngine as loose mocks.
    /// Does NOT clear existing loose mocks — project mocks are additive.
    public static func applyAll() {
        let mocks = loadAll()
        for mock in mocks {
            MockEngine.shared.addLooseMock(mock.toUnifiedMock())
        }
    }

    /// Count of project mocks.
    public static func count() -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: mockingDir) else { return 0 }
        return files.filter { $0.hasSuffix(".json") }.count
    }
}

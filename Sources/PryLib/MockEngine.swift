import Foundation

/// Centralized mock resolution engine. Manages loose and scenario mocks with priority.
/// Loose mocks take priority over scenario mocks (ad-hoc overrides).
public final class MockEngine {
    public static let shared = MockEngine()

    private var looseMocks: [UnifiedMock] = []
    private var scenarioMocks: [UnifiedMock] = []
    private let queue = DispatchQueue(label: "dev.pry.mockengine")

    private init() {}

    // MARK: - Lookup

    /// Find a matching mock. Loose mocks checked first (higher priority).
    public func findMock(path: String, host: String, method: String) -> UnifiedMock? {
        queue.sync {
            print("[MockEngine] findMock path=\(path) host=\(host) method=\(method) loose=\(looseMocks.count) scenario=\(scenarioMocks.count)")
            for m in looseMocks + scenarioMocks {
                let matches = m.matches(path: path, host: host, method: method)
                print("[MockEngine]   \(matches ? "✅" : "❌") pattern=\(m.pattern) mockHost=\(m.host ?? "nil") mockMethod=\(m.method ?? "nil")")
            }
            // Loose mocks first (ad-hoc overrides)
            if let mock = looseMocks.first(where: { $0.matches(path: path, host: host, method: method) }) {
                return mock
            }
            // Scenario mocks second
            return scenarioMocks.first(where: { $0.matches(path: path, host: host, method: method) })
        }
    }

    // MARK: - Loose Mocks

    public func addLooseMock(_ mock: UnifiedMock) {
        queue.sync { looseMocks.append(mock) }
    }

    public func removeLooseMock(id: String) {
        queue.sync { looseMocks.removeAll { $0.id == id } }
    }

    public func looseMockList() -> [UnifiedMock] {
        queue.sync { looseMocks }
    }

    // MARK: - Scenario Mocks

    public func loadScenarioMocks(_ mocks: [UnifiedMock]) {
        queue.sync { scenarioMocks = mocks }
    }

    public func clearScenarioMocks() {
        queue.sync { scenarioMocks = [] }
    }

    // MARK: - All Mocks

    public func activeMocks() -> [UnifiedMock] {
        queue.sync { looseMocks + scenarioMocks }
    }

    public func clearAll() {
        queue.sync {
            looseMocks = []
            scenarioMocks = []
        }
    }

    public func clearLooseMocks() {
        queue.sync { looseMocks = [] }
    }

    /// Total count of active mocks.
    public var count: Int {
        queue.sync { looseMocks.count + scenarioMocks.count }
    }
}

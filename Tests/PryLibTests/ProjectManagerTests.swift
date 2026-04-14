import XCTest
@testable import PryLib

final class ProjectManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Clean up projects
        for name in ProjectManager.list() {
            ProjectManager.delete(name: name)
        }
        ProjectManager.deactivate()
        MockEngine.shared.clearAll()
    }

    override func tearDown() {
        for name in ProjectManager.list() {
            ProjectManager.delete(name: name)
        }
        ProjectManager.deactivate()
        MockEngine.shared.clearAll()
        super.tearDown()
    }

    // MARK: - Project CRUD

    func testCreateProject() throws {
        try ProjectManager.create(name: "test-project")
        XCTAssertTrue(ProjectManager.list().contains("test-project"))
    }

    func testListProjects() throws {
        try ProjectManager.create(name: "beta")
        try ProjectManager.create(name: "alpha")
        XCTAssertEqual(ProjectManager.list(), ["alpha", "beta"])
    }

    func testDeleteProject() throws {
        try ProjectManager.create(name: "to-delete")
        ProjectManager.delete(name: "to-delete")
        XCTAssertFalse(ProjectManager.list().contains("to-delete"))
    }

    func testLoadProject() throws {
        try ProjectManager.create(name: "loadable")
        let loaded = ProjectManager.load(name: "loadable")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "loadable")
    }

    func testLoadNonexistentProjectReturnsNil() {
        XCTAssertNil(ProjectManager.load(name: "nonexistent"))
    }

    func testDeleteActiveProjectDeactivates() throws {
        try ProjectManager.create(name: "proj")
        try ProjectManager.createScenario(project: "proj", name: "scene")
        var scenario = ProjectManager.loadScenario(project: "proj", scenario: "scene")!
        scenario.mocks = [UnifiedMock(pattern: "/test", status: 200, body: "{}")]
        try ProjectManager.saveScenario(scenario, project: "proj")
        _ = ProjectManager.activate(project: "proj", scenario: "scene")

        XCTAssertEqual(ProjectManager.activeProject(), "proj")
        ProjectManager.delete(name: "proj")
        XCTAssertNil(ProjectManager.activeProject())
        XCTAssertNil(ProjectManager.activeScenario())
    }

    // MARK: - Scenario CRUD within Project

    func testCreateScenario() throws {
        try ProjectManager.create(name: "proj")
        try ProjectManager.createScenario(project: "proj", name: "scene1")
        let scenarios = ProjectManager.listScenarios(project: "proj")
        XCTAssertEqual(scenarios, ["scene1"])
    }

    func testListScenarios() throws {
        try ProjectManager.create(name: "proj")
        try ProjectManager.createScenario(project: "proj", name: "beta")
        try ProjectManager.createScenario(project: "proj", name: "alpha")
        XCTAssertEqual(ProjectManager.listScenarios(project: "proj"), ["alpha", "beta"])
    }

    func testDeleteScenario() throws {
        try ProjectManager.create(name: "proj")
        try ProjectManager.createScenario(project: "proj", name: "to-delete")
        ProjectManager.deleteScenario(project: "proj", scenario: "to-delete")
        XCTAssertTrue(ProjectManager.listScenarios(project: "proj").isEmpty)
    }

    func testLoadScenario() throws {
        try ProjectManager.create(name: "proj")
        try ProjectManager.createScenario(project: "proj", name: "scene")
        let loaded = ProjectManager.loadScenario(project: "proj", scenario: "scene")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "scene")
    }

    func testLoadNonexistentScenarioReturnsNil() throws {
        try ProjectManager.create(name: "proj")
        XCTAssertNil(ProjectManager.loadScenario(project: "proj", scenario: "nope"))
    }

    func testSaveScenarioWithData() throws {
        try ProjectManager.create(name: "proj")
        var scenario = Scenario(name: "with-data")
        scenario.watchlist = ["api.example.com"]
        scenario.mocks = [UnifiedMock(pattern: "/api/test", status: 200, body: "{\"ok\":true}")]
        scenario.breakpoints = ["/api/login"]
        try ProjectManager.saveScenario(scenario, project: "proj")

        let loaded = ProjectManager.loadScenario(project: "proj", scenario: "with-data")
        XCTAssertEqual(loaded?.watchlist, ["api.example.com"])
        XCTAssertEqual(loaded?.mocks.count, 1)
        XCTAssertEqual(loaded?.mocks.first?.pattern, "/api/test")
        XCTAssertEqual(loaded?.breakpoints, ["/api/login"])
    }

    func testDeleteActiveScenarioDeactivates() throws {
        try ProjectManager.create(name: "proj")
        try ProjectManager.createScenario(project: "proj", name: "scene")
        var scenario = ProjectManager.loadScenario(project: "proj", scenario: "scene")!
        scenario.mocks = [UnifiedMock(pattern: "/test", status: 200, body: "{}")]
        try ProjectManager.saveScenario(scenario, project: "proj")
        _ = ProjectManager.activate(project: "proj", scenario: "scene")

        XCTAssertEqual(ProjectManager.activeScenario(), "scene")
        ProjectManager.deleteScenario(project: "proj", scenario: "scene")
        XCTAssertNil(ProjectManager.activeScenario())
    }

    // MARK: - Activation

    func testActivateAndDeactivate() throws {
        try ProjectManager.create(name: "proj")
        try ProjectManager.createScenario(project: "proj", name: "scene")

        // Add a mock to the scenario
        var scenario = ProjectManager.loadScenario(project: "proj", scenario: "scene")!
        scenario.mocks = [UnifiedMock(pattern: "/test", status: 200, body: "{}")]
        try ProjectManager.saveScenario(scenario, project: "proj")

        // Activate
        let result = ProjectManager.activate(project: "proj", scenario: "scene")
        XCTAssertTrue(result)
        XCTAssertEqual(ProjectManager.activeProject(), "proj")
        XCTAssertEqual(ProjectManager.activeScenario(), "scene")
        XCTAssertEqual(MockEngine.shared.count, 1)

        // Deactivate
        ProjectManager.deactivate()
        XCTAssertNil(ProjectManager.activeProject())
        XCTAssertNil(ProjectManager.activeScenario())
        XCTAssertEqual(MockEngine.shared.count, 0)
    }

    func testActivateNonexistent() {
        let result = ProjectManager.activate(project: "nope", scenario: "nope")
        XCTAssertFalse(result)
    }

    func testActiveReturnsNilWhenNone() {
        XCTAssertNil(ProjectManager.activeProject())
        XCTAssertNil(ProjectManager.activeScenario())
    }

    func testActivateAppliesWatchlist() throws {
        try ProjectManager.create(name: "proj")
        var scenario = Scenario(name: "scene")
        scenario.watchlist = ["api.test.com"]
        try ProjectManager.saveScenario(scenario, project: "proj")

        _ = ProjectManager.activate(project: "proj", scenario: "scene")
        XCTAssertTrue(Watchlist.load().contains("api.test.com"))

        ProjectManager.deactivate()
        XCTAssertFalse(Watchlist.load().contains("api.test.com"))
    }

    func testActivateAppliesTrackingDomainsToWatchlist() throws {
        try ProjectManager.create(name: "proj")
        let config = TrackingConfig(domains: ["tracked.example.com"], mode: .domain)
        ProjectManager.updateTracking(project: "proj", config: config)
        try ProjectManager.createScenario(project: "proj", name: "scene")

        _ = ProjectManager.activate(project: "proj", scenario: "scene")
        XCTAssertTrue(Watchlist.load().contains("tracked.example.com"))

        ProjectManager.deactivate()
    }

    // MARK: - Copy Mocks

    func testCopyMocks() throws {
        try ProjectManager.create(name: "proj")
        try ProjectManager.createScenario(project: "proj", name: "source")
        try ProjectManager.createScenario(project: "proj", name: "dest")

        var source = ProjectManager.loadScenario(project: "proj", scenario: "source")!
        source.mocks = [
            UnifiedMock(pattern: "/api/a", body: "{}"),
            UnifiedMock(pattern: "/api/b", body: "{}")
        ]
        try ProjectManager.saveScenario(source, project: "proj")

        let count = ProjectManager.copyMocks(fromProject: "proj", fromScenario: "source",
                                              toProject: "proj", toScenario: "dest")
        XCTAssertEqual(count, 2)

        let dest = ProjectManager.loadScenario(project: "proj", scenario: "dest")!
        XCTAssertEqual(dest.mocks.count, 2)
    }

    func testCopyMocksBetweenProjects() throws {
        try ProjectManager.create(name: "projA")
        try ProjectManager.create(name: "projB")
        try ProjectManager.createScenario(project: "projA", name: "source")
        try ProjectManager.createScenario(project: "projB", name: "dest")

        var source = ProjectManager.loadScenario(project: "projA", scenario: "source")!
        source.mocks = [UnifiedMock(pattern: "/api/x", body: "{}")]
        try ProjectManager.saveScenario(source, project: "projA")

        let count = ProjectManager.copyMocks(fromProject: "projA", fromScenario: "source",
                                              toProject: "projB", toScenario: "dest")
        XCTAssertEqual(count, 1)

        let dest = ProjectManager.loadScenario(project: "projB", scenario: "dest")!
        XCTAssertEqual(dest.mocks.count, 1)
        XCTAssertEqual(dest.mocks[0].pattern, "/api/x")
    }

    func testCopyMocksFromNonexistentReturnsZero() {
        let count = ProjectManager.copyMocks(fromProject: "nope", fromScenario: "nope",
                                              toProject: "nope", toScenario: "nope")
        XCTAssertEqual(count, 0)
    }

    // MARK: - Tracking Config

    func testTrackingConfig() throws {
        try ProjectManager.create(name: "proj")
        let config = TrackingConfig(domains: ["api.example.com"], mode: .domain)
        ProjectManager.updateTracking(project: "proj", config: config)

        let loaded = ProjectManager.load(name: "proj")!
        XCTAssertEqual(loaded.tracking.domains, ["api.example.com"])
        XCTAssertEqual(loaded.tracking.mode, .domain)
    }

    func testTrackingMatchesDomainMode() {
        let config = TrackingConfig(domains: ["api.example.com"], userAgents: ["MyApp/*"], mode: .domain)
        XCTAssertTrue(config.matches(host: "api.example.com", userAgent: nil))
        XCTAssertFalse(config.matches(host: "other.com", userAgent: nil))
    }

    func testTrackingMatchesUserAgentMode() {
        let config = TrackingConfig(domains: [], userAgents: ["MyApp/*"], mode: .userAgent)
        XCTAssertTrue(config.matches(host: "any.com", userAgent: "MyApp/1.0"))
        XCTAssertFalse(config.matches(host: "any.com", userAgent: "Safari/1.0"))
    }

    func testTrackingMatchesBothMode() {
        let config = TrackingConfig(domains: ["api.example.com"], userAgents: ["MyApp/*"], mode: .both)
        XCTAssertTrue(config.matches(host: "api.example.com", userAgent: "MyApp/1.0"))
        XCTAssertFalse(config.matches(host: "api.example.com", userAgent: "Safari"))
        XCTAssertFalse(config.matches(host: "other.com", userAgent: "MyApp/1.0"))
    }

    func testTrackingWildcardDomain() {
        let config = TrackingConfig(domains: ["*.example.com"], mode: .domain)
        XCTAssertTrue(config.matches(host: "api.example.com", userAgent: nil))
        XCTAssertTrue(config.matches(host: "example.com", userAgent: nil))
        XCTAssertFalse(config.matches(host: "other.com", userAgent: nil))
    }

    func testTrackingSubdomainMatching() {
        let config = TrackingConfig(domains: ["example.com"], mode: .domain)
        XCTAssertTrue(config.matches(host: "example.com", userAgent: nil))
        XCTAssertTrue(config.matches(host: "api.example.com", userAgent: nil))
        XCTAssertFalse(config.matches(host: "notexample.com", userAgent: nil))
    }

    func testTrackingEmptyDomainsNeverMatches() {
        let config = TrackingConfig(domains: [], mode: .domain)
        XCTAssertFalse(config.matches(host: "anything.com", userAgent: nil))
    }

    // MARK: - Find Project

    func testFindProject() throws {
        try ProjectManager.create(name: "proj")
        let config = TrackingConfig(domains: ["api.example.com"], mode: .domain)
        ProjectManager.updateTracking(project: "proj", config: config)

        XCTAssertEqual(ProjectManager.findProject(host: "api.example.com", userAgent: nil), "proj")
        XCTAssertNil(ProjectManager.findProject(host: "unknown.com", userAgent: nil))
    }

    func testFindProjectWithMultipleProjects() throws {
        try ProjectManager.create(name: "projA")
        try ProjectManager.create(name: "projB")
        ProjectManager.updateTracking(project: "projA",
                                       config: TrackingConfig(domains: ["a.example.com"], mode: .domain))
        ProjectManager.updateTracking(project: "projB",
                                       config: TrackingConfig(domains: ["b.example.com"], mode: .domain))

        XCTAssertEqual(ProjectManager.findProject(host: "a.example.com", userAgent: nil), "projA")
        XCTAssertEqual(ProjectManager.findProject(host: "b.example.com", userAgent: nil), "projB")
        XCTAssertNil(ProjectManager.findProject(host: "c.example.com", userAgent: nil))
    }

    // MARK: - Auto-learn User Agent

    func testAutoLearnUserAgent() throws {
        try ProjectManager.create(name: "proj")
        let config = TrackingConfig(domains: ["api.example.com"], mode: .domain, autoDetect: true)
        ProjectManager.updateTracking(project: "proj", config: config)

        ProjectManager.autoLearnUserAgent(project: "proj", userAgent: "MyApp/1.0")

        let loaded = ProjectManager.load(name: "proj")!
        XCTAssertTrue(loaded.tracking.userAgents.contains("MyApp/1.0"))
    }

    func testAutoLearnUserAgentDoesNotDuplicate() throws {
        try ProjectManager.create(name: "proj")
        let config = TrackingConfig(domains: ["api.example.com"], userAgents: ["MyApp/1.0"],
                                     mode: .domain, autoDetect: true)
        ProjectManager.updateTracking(project: "proj", config: config)

        ProjectManager.autoLearnUserAgent(project: "proj", userAgent: "MyApp/1.0")

        let loaded = ProjectManager.load(name: "proj")!
        XCTAssertEqual(loaded.tracking.userAgents.filter { $0 == "MyApp/1.0" }.count, 1)
    }

    func testAutoLearnUserAgentSkipsWhenDisabled() throws {
        try ProjectManager.create(name: "proj")
        let config = TrackingConfig(domains: ["api.example.com"], mode: .domain, autoDetect: false)
        ProjectManager.updateTracking(project: "proj", config: config)

        ProjectManager.autoLearnUserAgent(project: "proj", userAgent: "MyApp/1.0")

        let loaded = ProjectManager.load(name: "proj")!
        XCTAssertTrue(loaded.tracking.userAgents.isEmpty)
    }

    func testAutoLearnUserAgentSkipsEmpty() throws {
        try ProjectManager.create(name: "proj")
        let config = TrackingConfig(domains: ["api.example.com"], mode: .domain, autoDetect: true)
        ProjectManager.updateTracking(project: "proj", config: config)

        ProjectManager.autoLearnUserAgent(project: "proj", userAgent: "  ")

        let loaded = ProjectManager.load(name: "proj")!
        XCTAssertTrue(loaded.tracking.userAgents.isEmpty)
    }
}

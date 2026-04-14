import Foundation
import Observation
import PryLib

@available(macOS 14, *)
@Observable
@MainActor
public final class ProjectUIManager {
    public var projects: [String] = []
    public var activeProject: String?
    public var activeScenario: String?

    public init() {
        reload()
        // Re-activate scenario on app launch if one was active
        restoreActiveScenario()
    }

    public func reload() {
        projects = ProjectManager.list()
        activeProject = ProjectManager.activeProject()
        activeScenario = ProjectManager.activeScenario()
    }

    /// On app launch, if a scenario was active, re-load its mocks into MockEngine.
    private func restoreActiveScenario() {
        guard let project = activeProject, let scenario = activeScenario else { return }
        _ = ProjectManager.activate(project: project, scenario: scenario)
    }

    public func createProject(name: String) throws {
        try ProjectManager.create(name: name)
        reload()
    }

    public func deleteProject(name: String) {
        ProjectManager.delete(name: name)
        reload()
    }

    public func listScenarios(project: String) -> [String] {
        ProjectManager.listScenarios(project: project)
    }

    public func createScenario(project: String, name: String) throws {
        try ProjectManager.createScenario(project: project, name: name)
        reload()
    }

    public func deleteScenario(project: String, scenario: String) {
        ProjectManager.deleteScenario(project: project, scenario: scenario)
        reload()
    }

    public func loadScenario(project: String, scenario: String) -> Scenario? {
        ProjectManager.loadScenario(project: project, scenario: scenario)
    }

    public func saveScenario(_ scenario: Scenario, project: String) throws {
        try ProjectManager.saveScenario(scenario, project: project)
        reload()
    }

    public func activate(project: String, scenario: String) {
        _ = ProjectManager.activate(project: project, scenario: scenario)
        reload()
    }

    public func deactivate() {
        ProjectManager.deactivate()
        reload()
    }

    public func copyMocks(fromProject: String, fromScenario: String, toProject: String, toScenario: String) -> Int {
        let count = ProjectManager.copyMocks(fromProject: fromProject, fromScenario: fromScenario, toProject: toProject, toScenario: toScenario)
        reload()
        return count
    }

    public func loadProject(name: String) -> Project? {
        ProjectManager.load(name: name)
    }

    public func updateTracking(project: String, config: TrackingConfig) {
        ProjectManager.updateTracking(project: project, config: config)
        reload()
    }

    public var activeLabel: String? {
        guard let p = activeProject, let s = activeScenario else { return nil }
        return "\(p) / \(s)"
    }
}

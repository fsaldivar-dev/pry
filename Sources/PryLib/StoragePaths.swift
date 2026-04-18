import Foundation

/// Centralized storage path resolution. Uses ~/.pry/ as the root so the app works
/// regardless of working directory (CLI from project, GUI from /Applications/).
public enum StoragePaths {
    /// Root directory for all Pry data: ~/.pry/
    public static var root: String {
        NSHomeDirectory() + "/.pry"
    }

    // MARK: - Config files

    public static var configFile: String { "\(root)/config" }
    public static var watchFile: String { "\(root)/watch" }

    // MARK: - Runtime state (formerly /tmp/pry.*)

    public static var logFile: String { "\(root)/pry.log" }
    public static var pidFile: String { "\(root)/pry.pid" }
    public static var mockFile: String { "\(root)/mocks" }
    public static var blocksFile: String { "\(root)/blocklist" }
    public static var headersFile: String { "\(root)/headers" }
    public static var mapsFile: String { "\(root)/maps" }
    public static var redirectsFile: String { "\(root)/redirects" }
    public static var dnsFile: String { "\(root)/dns" }
    public static var overridesFile: String { "\(root)/overrides" }
    public static var breakpointsFile: String { "\(root)/breakpoints" }

    // MARK: - Directories

    public static var projectsDir: String { "\(root)/projects" }
    public static var scenariosDir: String { "\(root)/scenarios" }
    public static var recordingsDir: String { "\(root)/recordings" }
    public static var mockingDir: String { "\(root)/mocking" }
    public static var caDir: String { "\(root)/ca" }
    public static var sessionsDir: String { "\(root)/sessions" }
    public static var sessionFile: String { "\(sessionsDir)/last.jsonl" }

    // MARK: - Active state

    public static var activeProjectFile: String { "\(root)/active-project" }
    public static var activeScenarioFile: String { "\(root)/active-scenario" }
    public static var proxyStateFile: String { "\(root)/proxy.state" }

    /// Ensure the root directory exists.
    public static func ensureRoot() {
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }
}

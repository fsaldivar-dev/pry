import Foundation

/// Persistent proxy state — written when system proxy is enabled, cleared on disable.
/// Survives crashes. Used by ProxyGuard to detect orphaned proxy configurations.
public struct ProxyState: Codable {
    public let port: Int
    public let pid: Int32
    public let networkService: String
    public let enabledAt: Date

    public static let stateFile = NSHomeDirectory() + "/.pry/proxy.state"

    /// Save proxy state atomically to disk.
    public static func save(port: Int, pid: Int32, networkService: String) {
        let state = ProxyState(port: port, pid: pid, networkService: networkService, enabledAt: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        // Ensure directory exists
        let dir = (stateFile as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: stateFile), options: .atomic)
    }

    /// Load proxy state from disk. Returns nil if file doesn't exist or is corrupted.
    public static func load() -> ProxyState? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: stateFile)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ProxyState.self, from: data)
    }

    /// Delete the state file.
    public static func clear() {
        try? FileManager.default.removeItem(atPath: stateFile)
    }

    /// Check if the recorded proxy state is orphaned (process is dead).
    /// Returns the state if orphaned, nil if alive or no state file.
    public static func isOrphaned() -> ProxyState? {
        guard let state = load() else { return nil }
        // kill with signal 0 checks if process exists without sending a signal
        if kill(state.pid, 0) != 0 {
            // Process is dead — orphan detected
            return state
        }
        return nil
    }
}

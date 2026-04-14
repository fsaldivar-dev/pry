import Foundation

/// Orchestrates proxy cleanup to prevent orphaned system proxy configurations.
/// Call `cleanupIfNeeded()` on every app/CLI launch.
public struct ProxyGuard {

    /// Check for orphaned proxy config and clean up if found.
    /// Should be called early in every CLI invocation and GUI launch.
    public static func cleanupIfNeeded() {
        // Primary: check state file for orphaned process
        if let orphan = ProxyState.isOrphaned() {
            SystemProxy.disable(service: orphan.networkService)
            ProxyState.clear()
            // Also clean up stale PID file
            try? FileManager.default.removeItem(atPath: Config.pidFile)
            fputs("[ProxyGuard] Cleaned up orphaned proxy config (PID \(orphan.pid) on \(orphan.networkService))\n", stderr)
            return
        }

        // Fallback: no state file, but system proxy might still be pointing at us
        // This handles the case where state file was lost
        if ProxyState.load() == nil {
            let port = Config.port()
            if SystemProxy.isEnabled(port: port) && !isProcessListeningOn(port: port) {
                SystemProxy.disable()
                fputs("[ProxyGuard] Cleaned up stale system proxy on port \(port)\n", stderr)
            }
        }
    }

    /// Install signal handlers that clean up proxy state on termination.
    public static func installSignalHandlers() {
        signal(SIGINT) { _ in
            ProxyGuard.emergencyCleanup()
            exit(0)
        }
        signal(SIGTERM) { _ in
            ProxyGuard.emergencyCleanup()
            exit(0)
        }
        signal(SIGHUP) { _ in
            ProxyGuard.emergencyCleanup()
            exit(0)
        }
    }

    /// Install atexit handler for normal exit paths.
    public static func installAtexitHandler() {
        atexit {
            // Only clean up if we still have a state file with our PID
            if let state = ProxyState.load(),
               state.pid == ProcessInfo.processInfo.processIdentifier {
                SystemProxy.disable(service: state.networkService)
                ProxyState.clear()
                try? FileManager.default.removeItem(atPath: Config.pidFile)
            }
        }
    }

    /// Emergency cleanup — called from signal handlers.
    /// Must be async-signal-safe where possible.
    private static func emergencyCleanup() {
        if let state = ProxyState.load() {
            SystemProxy.disable(service: state.networkService)
        }
        ProxyState.clear()
        try? FileManager.default.removeItem(atPath: Config.pidFile)
    }

    /// Check if any process is listening on the given port.
    private static func isProcessListeningOn(port: Int) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-i", ":\(port)", "-t"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }
}

import Foundation

/// Manages URL patterns for request breakpoints
public class BreakpointStore {
    public static let shared = BreakpointStore()

    private let queue = DispatchQueue(label: "pry.breakpoints")
    private var patterns: [String] = []

    private static let breakpointsFile = "/tmp/pry.breakpoints"

    init() {
        load()
    }

    /// Add a URL pattern to break on (e.g., "/api/login", "*.myapp.com")
    public func add(_ pattern: String) {
        queue.sync {
            if !patterns.contains(pattern) {
                patterns.append(pattern)
            }
        }
        save()
    }

    /// Remove a breakpoint pattern
    public func remove(_ pattern: String) {
        queue.sync {
            patterns.removeAll { $0 == pattern }
        }
        save()
    }

    /// Clear all breakpoints
    public func clearAll() {
        queue.sync { patterns.removeAll() }
        save()
    }

    /// Get all patterns
    public func all() -> [String] {
        queue.sync { patterns }
    }

    /// Check if a URL should be paused
    public func shouldBreak(url: String, host: String) -> Bool {
        return queue.sync {
            for pattern in patterns {
                if matchesPattern(pattern, url: url, host: host) {
                    return true
                }
            }
            return false
        }
    }

    private func matchesPattern(_ pattern: String, url: String, host: String) -> Bool {
        // Glob-style matching
        if pattern.contains("*") {
            let regex = pattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")
            return (try? NSRegularExpression(pattern: "^\(regex)", options: []))
                .map { $0.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
                    || $0.firstMatch(in: host, range: NSRange(host.startIndex..., in: host)) != nil }
                ?? false
        }

        // Simple prefix match on URL path
        return url.contains(pattern) || host.contains(pattern)
    }

    private func save() {
        let content = queue.sync { patterns.joined(separator: "\n") }
        try? content.write(toFile: Self.breakpointsFile, atomically: true, encoding: .utf8)
    }

    private func load() {
        guard let content = try? String(contentsOfFile: Self.breakpointsFile, encoding: .utf8) else { return }
        let loaded = content.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        queue.sync { patterns = loaded }
    }
}

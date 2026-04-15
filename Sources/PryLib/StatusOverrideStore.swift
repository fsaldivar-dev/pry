import Foundation

/// Manages status code overrides. Quick way to simulate error responses without full mocks.
/// Stored in /tmp/pry.overrides as pattern\tstatus per line.
public struct StatusOverrideStore {
    public static var file: String {
        StoragePaths.ensureRoot()
        return StoragePaths.overridesFile
    }

    public struct Override {
        public let pattern: String
        public let status: UInt
    }

    /// Save a status override for a URL pattern.
    public static func save(pattern: String, status: UInt) {
        let entry = "\(pattern)\t\(status)\n"
        if let data = entry.data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: file) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? entry.write(toFile: file, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Load all overrides.
    public static func loadAll() -> [Override] {
        guard let content = try? String(contentsOfFile: file, encoding: .utf8) else { return [] }
        return content.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let status = UInt(parts[1]) else { return nil }
            return Override(pattern: String(parts[0]), status: status)
        }
    }

    /// Match a URL against overrides. Returns the status code if matched.
    public static func match(url: String, host: String) -> UInt? {
        let overrides = loadAll()
        for override in overrides {
            // Check if pattern matches URL path or host
            if url.contains(override.pattern) || host.contains(override.pattern) {
                return override.status
            }
            // Glob pattern support
            if override.pattern.contains("*") {
                let regex = "^" + NSRegularExpression.escapedPattern(for: override.pattern)
                    .replacingOccurrences(of: "\\*", with: ".*") + "$"
                if let re = try? NSRegularExpression(pattern: regex),
                   re.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil {
                    return override.status
                }
            }
        }
        return nil
    }

    /// Remove a specific override by pattern.
    public static func remove(pattern: String) {
        let overrides = loadAll().filter { $0.pattern != pattern }
        let content = overrides.map { "\($0.pattern)\t\($0.status)" }.joined(separator: "\n")
        try? (content.isEmpty ? "" : content + "\n").write(toFile: file, atomically: true, encoding: .utf8)
    }

    /// Clear all overrides.
    public static func clear() {
        try? "".write(toFile: file, atomically: true, encoding: .utf8)
    }
}

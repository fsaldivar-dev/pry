import Foundation

/// Source provenance for a mock — tracks where the mock came from.
public enum MockSource: Codable, Equatable {
    case loose
    case scenario(project: String, scenario: String)
    case recording(name: String)

    public var label: String {
        switch self {
        case .loose: return "loose"
        case .scenario(_, let scenario): return scenario
        case .recording(let name): return name
        }
    }
}

/// Unified mock that replaces the flat path->body format AND status overrides.
/// Supports method matching, custom status codes, headers, delay, and provenance tracking.
public struct UnifiedMock: Codable, Equatable, Identifiable {
    public let id: String
    public let method: String?          // nil = match any method
    public let pattern: String          // URL path pattern (prefix match, glob with *)
    public let host: String?            // nil = match any host
    public let status: UInt             // HTTP status code
    public let headers: [String: String]?
    public let body: String
    public let contentType: String?     // default "application/json"
    public let delay: Int?              // milliseconds before responding
    public let notes: String?
    public let source: MockSource?
    public var isEnabled: Bool

    public init(id: String = UUID().uuidString, method: String? = nil, pattern: String, host: String? = nil,
                status: UInt = 200, headers: [String: String]? = nil, body: String = "{}",
                contentType: String? = nil, delay: Int? = nil, notes: String? = nil,
                source: MockSource? = nil, isEnabled: Bool = true) {
        self.id = id; self.method = method; self.pattern = pattern; self.host = host
        self.status = status; self.headers = headers; self.body = body
        self.contentType = contentType; self.delay = delay; self.notes = notes
        self.source = source; self.isEnabled = isEnabled
    }

    /// Check if this mock matches a request.
    public func matches(path: String, host: String, method: String) -> Bool {
        guard isEnabled else { return false }

        // Method check (nil = match all)
        if let m = self.method, m.uppercased() != method.uppercased() { return false }

        // Host check (nil = match all)
        if let h = self.host, !host.lowercased().contains(h.lowercased()) { return false }

        // Pattern check
        if pattern.contains("*") {
            // Glob pattern
            let regex = "^" + NSRegularExpression.escapedPattern(for: pattern)
                .replacingOccurrences(of: "\\*", with: ".*") + "$"
            if let re = try? NSRegularExpression(pattern: regex),
               re.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil {
                return true
            }
            return false
        } else {
            return path.hasPrefix(pattern)
        }
    }
}

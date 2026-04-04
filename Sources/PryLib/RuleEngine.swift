import Foundation

/// Actions that can be applied by a rule
public enum RuleAction: Equatable {
    case setHeader(name: String, value: String)
    case removeHeader(name: String)
    case replaceHost(String)
    case replacePort(Int)
    case replacePath(String)
    case setStatus(UInt)
    case setBody(String)
    case delay(Int)  // milliseconds
    case drop
}

/// A rule with a URL/host pattern and list of actions
public struct Rule {
    public let pattern: String
    public let method: String?  // nil = any method
    public let actions: [RuleAction]
}

/// Result of applying request rules
public struct RuleResult {
    public let shouldDrop: Bool
    public let delayMs: Int?
    public let replaceHost: String?
    public let replacePort: Int?
}

/// Declarative rule engine for request/response modification
public struct RuleEngine {
    private static var rules: [Rule] = []

    // MARK: - Parse .pryrules format

    public static func parse(content: String) -> [Rule] {
        var result: [Rule] = []
        var currentPattern: String?
        var currentMethod: String?
        var currentActions: [RuleAction] = []

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                // Blank line or comment — finalize current rule if any
                if let pattern = currentPattern, !currentActions.isEmpty {
                    result.append(Rule(pattern: pattern, method: currentMethod, actions: currentActions))
                    currentPattern = nil
                    currentMethod = nil
                    currentActions = []
                }
                continue
            }

            if trimmed.hasPrefix("rule ") {
                // Finalize previous rule
                if let pattern = currentPattern, !currentActions.isEmpty {
                    result.append(Rule(pattern: pattern, method: currentMethod, actions: currentActions))
                }
                // Parse new rule pattern
                let patternStr = extractQuoted(from: trimmed, after: "rule ")
                let parts = patternStr.split(separator: " ", maxSplits: 1)
                if parts.count == 2 {
                    let possibleMethod = String(parts[0]).uppercased()
                    if ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"].contains(possibleMethod) {
                        currentMethod = possibleMethod
                        currentPattern = String(parts[1])
                    } else {
                        currentMethod = nil
                        currentPattern = patternStr
                    }
                } else {
                    currentMethod = nil
                    currentPattern = patternStr
                }
                currentActions = []
            } else if let action = parseAction(trimmed) {
                currentActions.append(action)
            }
        }

        // Finalize last rule
        if let pattern = currentPattern, !currentActions.isEmpty {
            result.append(Rule(pattern: pattern, method: currentMethod, actions: currentActions))
        }

        return result
    }

    private static func parseAction(_ line: String) -> RuleAction? {
        if line.hasPrefix("set-header ") {
            let rest = String(line.dropFirst("set-header ".count))
            let parts = rest.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let name = String(parts[0])
            let value = stripQuotes(String(parts[1]))
            return .setHeader(name: name, value: value)
        }
        if line.hasPrefix("remove-header ") {
            let name = String(line.dropFirst("remove-header ".count)).trimmingCharacters(in: .whitespaces)
            return .removeHeader(name: name)
        }
        if line.hasPrefix("replace-host ") {
            let host = String(line.dropFirst("replace-host ".count)).trimmingCharacters(in: .whitespaces)
            return .replaceHost(host)
        }
        if line.hasPrefix("replace-port ") {
            let portStr = String(line.dropFirst("replace-port ".count)).trimmingCharacters(in: .whitespaces)
            if let port = Int(portStr) { return .replacePort(port) }
        }
        if line.hasPrefix("replace-path ") {
            let path = stripQuotes(String(line.dropFirst("replace-path ".count)).trimmingCharacters(in: .whitespaces))
            return .replacePath(path)
        }
        if line.hasPrefix("set-status ") {
            let statusStr = String(line.dropFirst("set-status ".count)).trimmingCharacters(in: .whitespaces)
            if let status = UInt(statusStr) { return .setStatus(status) }
        }
        if line.hasPrefix("set-body ") {
            let body = stripQuotes(String(line.dropFirst("set-body ".count)).trimmingCharacters(in: .whitespaces))
            return .setBody(body)
        }
        if line.hasPrefix("delay ") {
            let msStr = String(line.dropFirst("delay ".count)).trimmingCharacters(in: .whitespaces)
            if let ms = Int(msStr) { return .delay(ms) }
        }
        if line == "drop" {
            return .drop
        }
        return nil
    }

    // MARK: - Load / Store

    public static func loadFromFile(path: String) throws {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let parsed = parse(content: content)
        loadRules(parsed)
    }

    public static func loadRules(_ newRules: [Rule]) {
        rules = newRules
    }

    public static func all() -> [Rule] {
        rules
    }

    public static func clear() {
        rules = []
    }

    // MARK: - Match

    public static func matchingRules(for url: String, method: String) -> [Rule] {
        rules.filter { rule in
            if let ruleMethod = rule.method, ruleMethod != method.uppercased() {
                return false
            }
            return matchesPattern(rule.pattern, against: url)
        }
    }

    private static func matchesPattern(_ pattern: String, against url: String) -> Bool {
        if pattern.contains("*") {
            let regex = pattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")
            return (try? NSRegularExpression(pattern: "^\(regex)"))
                .map { $0.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil }
                ?? false
        }
        return url.contains(pattern)
    }

    // MARK: - Apply

    public static func applyRequestRules(rules: [Rule], headers: inout [(String, String)]) -> RuleResult {
        var shouldDrop = false
        var delayMs: Int?
        var replaceHost: String?
        var replacePort: Int?

        for rule in rules {
            for action in rule.actions {
                switch action {
                case .setHeader(let name, let value):
                    headers.removeAll { $0.0.lowercased() == name.lowercased() }
                    headers.append((name, value))
                case .removeHeader(let name):
                    headers.removeAll { $0.0.lowercased() == name.lowercased() }
                case .replaceHost(let host):
                    replaceHost = host
                case .replacePort(let port):
                    replacePort = port
                case .delay(let ms):
                    delayMs = ms
                case .drop:
                    shouldDrop = true
                default:
                    break // response-only actions
                }
            }
        }

        return RuleResult(shouldDrop: shouldDrop, delayMs: delayMs, replaceHost: replaceHost, replacePort: replacePort)
    }

    public static func applyResponseRules(rules: [Rule], statusCode: inout UInt, body: inout String?) {
        for rule in rules {
            for action in rule.actions {
                switch action {
                case .setStatus(let code):
                    statusCode = code
                case .setBody(let newBody):
                    body = newBody
                case .setHeader:
                    break // TODO: response headers
                default:
                    break
                }
            }
        }
    }

    // MARK: - Helpers

    private static func extractQuoted(from str: String, after prefix: String) -> String {
        let rest = String(str.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        return stripQuotes(rest)
    }

    private static func stripQuotes(_ s: String) -> String {
        var result = s
        if (result.hasPrefix("\"") && result.hasSuffix("\"")) ||
           (result.hasPrefix("'") && result.hasSuffix("'")) {
            result = String(result.dropFirst().dropLast())
        }
        return result
    }
}

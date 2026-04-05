import Foundation

public struct HeaderRewrite {
    public static let headersFile = "/tmp/pry.headers"

    public enum Action: String {
        case add
        case remove
    }

    public struct Rule {
        public let action: Action
        public let name: String
        public let value: String?
    }

    public static func addRule(name: String, value: String) {
        let entry = "add\t\(name)\t\(value)\n"
        appendToFile(entry)
    }

    public static func removeRule(name: String) {
        let entry = "remove\t\(name)\n"
        appendToFile(entry)
    }

    public static func loadAll() -> [Rule] {
        guard let content = try? String(contentsOfFile: headersFile, encoding: .utf8) else { return [] }
        return content.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { return nil }
            let action = Action(rawValue: parts[0]) ?? .add
            let name = parts[1]
            let value = parts.count > 2 ? parts[2] : nil
            return Rule(action: action, name: name, value: value)
        }
    }

    /// Apply all rewrite rules to a set of headers
    public static func apply(to headers: [(String, String)]) -> [(String, String)] {
        let rules = loadAll()
        guard !rules.isEmpty else { return headers }

        var result = headers
        for rule in rules {
            switch rule.action {
            case .add:
                if let value = rule.value {
                    result.append((rule.name, value))
                }
            case .remove:
                result.removeAll(where: { $0.0.lowercased() == rule.name.lowercased() })
            }
        }
        return result
    }

    public static func clear() {
        try? "".write(toFile: headersFile, atomically: true, encoding: .utf8)
    }

    private static func appendToFile(_ entry: String) {
        if let handle = FileHandle(forWritingAtPath: headersFile),
           let data = entry.data(using: .utf8) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? entry.write(toFile: headersFile, atomically: true, encoding: .utf8)
        }
    }
}

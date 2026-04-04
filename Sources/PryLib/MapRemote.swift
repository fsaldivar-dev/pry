import Foundation

public struct MapRemote {
    public static let redirectsFile = "/tmp/pry.redirects"

    public struct RedirectRule {
        public let sourceHost: String
        public let targetHost: String
    }

    public static func save(sourceHost: String, targetHost: String) {
        let src = sourceHost.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\t", with: "").replacingOccurrences(of: "\n", with: "")
        let tgt = targetHost.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\t", with: "").replacingOccurrences(of: "\n", with: "")
        guard !src.isEmpty, !tgt.isEmpty else { return }
        let entry = "\(src)\t\(tgt)\n"
        if let data = entry.data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: redirectsFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? entry.write(toFile: redirectsFile, atomically: true, encoding: .utf8)
            }
        }
    }

    public static func loadAll() -> [RedirectRule] {
        guard let content = try? String(contentsOfFile: redirectsFile, encoding: .utf8) else { return [] }
        return content.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            return RedirectRule(sourceHost: parts[0], targetHost: parts[1])
        }
    }

    public static func match(host: String) -> String? {
        let h = host.lowercased()
        for rule in loadAll() {
            if h == rule.sourceHost { return rule.targetHost }
        }
        return nil
    }

    public static func clear() {
        try? "".write(toFile: redirectsFile, atomically: true, encoding: .utf8)
    }
}

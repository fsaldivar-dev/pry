import Foundation

public struct MapRemote {
    public static let redirectsFile = "/tmp/pry.redirects"

    public struct RedirectRule {
        public let sourceHost: String
        public let targetHost: String
    }

    public static func save(sourceHost: String, targetHost: String) {
        let entry = "\(sourceHost)\t\(targetHost)\n"
        if let handle = FileHandle(forWritingAtPath: redirectsFile) {
            handle.seekToEndOfFile()
            handle.write(entry.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? entry.write(toFile: redirectsFile, atomically: true, encoding: .utf8)
        }
    }

    public static func loadAll() -> [RedirectRule] {
        guard let content = try? String(contentsOfFile: redirectsFile, encoding: .utf8) else { return [] }
        return content.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { return nil }
            return RedirectRule(sourceHost: parts[0], targetHost: parts[1])
        }
    }

    public static func match(host: String) -> String? {
        let lowerHost = host.lowercased()
        for rule in loadAll() {
            if rule.sourceHost.lowercased() == lowerHost {
                return rule.targetHost
            }
        }
        return nil
    }

    public static func clear() {
        try? "".write(toFile: redirectsFile, atomically: true, encoding: .utf8)
    }
}

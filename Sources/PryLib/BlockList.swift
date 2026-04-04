import Foundation

public struct BlockList {
    public static let blocksFile = "/tmp/pry.blocklist"

    public static func add(_ domain: String) {
        let sanitized = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return }
        let entry = "\(sanitized)\n"
        if let data = entry.data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: blocksFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? entry.write(toFile: blocksFile, atomically: true, encoding: .utf8)
            }
        }
    }

    public static func loadAll() -> [String] {
        guard let content = try? String(contentsOfFile: blocksFile, encoding: .utf8) else { return [] }
        return content.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    public static func isBlocked(_ host: String) -> Bool {
        let h = host.lowercased()
        for pattern in loadAll() {
            if pattern.hasPrefix("*.") {
                let suffix = String(pattern.dropFirst(1))
                if h.hasSuffix(suffix) || h == String(pattern.dropFirst(2)) { return true }
            } else if h == pattern {
                return true
            }
        }
        return false
    }

    public static func clear() {
        try? "".write(toFile: blocksFile, atomically: true, encoding: .utf8)
    }
}

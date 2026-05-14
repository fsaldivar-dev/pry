import Foundation

public struct BlockList {
    public static let blocksFile = "/tmp/pry.blocklist"

    public static func add(_ domain: String) {
        let entry = "\(domain)\n"
        if let handle = FileHandle(forWritingAtPath: blocksFile) {
            handle.seekToEndOfFile()
            handle.write(entry.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? entry.write(toFile: blocksFile, atomically: true, encoding: .utf8)
        }
    }

    public static func loadAll() -> [String] {
        guard let content = try? String(contentsOfFile: blocksFile, encoding: .utf8) else { return [] }
        return content.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    public static func isBlocked(_ host: String) -> Bool {
        let lowerHost = host.lowercased()
        for domain in loadAll() {
            let lowerDomain = domain.lowercased()
            if lowerDomain.hasPrefix("*.") {
                let suffix = String(lowerDomain.dropFirst(2))
                if lowerHost == suffix || lowerHost.hasSuffix("." + suffix) {
                    return true
                }
            } else if lowerHost == lowerDomain {
                return true
            }
        }
        return false
    }

    public static func clear() {
        try? "".write(toFile: blocksFile, atomically: true, encoding: .utf8)
    }
}

import Foundation

public struct Watchlist {
    public static var watchFile: String {
        StoragePaths.ensureRoot()
        return StoragePaths.watchFile
    }

    public static func load() -> Set<String> {
        var domains = Set<String>()

        // From .prywatch file
        if let content = try? String(contentsOfFile: watchFile, encoding: .utf8) {
            for line in content.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    domains.insert(trimmed.lowercased())
                }
            }
        }

        return domains
    }

    public static func add(_ domain: String) {
        var domains = load()
        domains.insert(domain.lowercased())
        save(domains)
    }

    public static func addFromFile(_ path: String) throws {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw ProxyError.mockFileNotFound(path)
        }
        var domains = load()
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                domains.insert(trimmed.lowercased())
            }
        }
        save(domains)
    }

    public static func remove(_ domain: String) {
        var domains = load()
        domains.remove(domain.lowercased())
        save(domains)
    }

    public static func matches(_ host: String) -> Bool {
        let domains = load()
        let lowerHost = host.lowercased()
        for domain in domains {
            if domain.hasPrefix("*.") {
                let suffix = String(domain.dropFirst(2))
                if lowerHost == suffix || lowerHost.hasSuffix("." + suffix) {
                    return true
                }
            } else if lowerHost == domain || lowerHost.hasSuffix("." + domain) {
                return true
            }
        }
        return false
    }

    private static func save(_ domains: Set<String>) {
        let content = domains.sorted().joined(separator: "\n") + "\n"
        try? content.write(toFile: watchFile, atomically: true, encoding: .utf8)
    }
}

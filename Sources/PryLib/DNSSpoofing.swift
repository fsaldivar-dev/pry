import Foundation

public struct DNSSpoofing {
    public static let dnsFile = "/tmp/pry.dns"

    public struct DNSRule {
        public let domain: String
        public let ip: String
    }

    public static func add(domain: String, ip: String) {
        let entry = "\(domain)\t\(ip)\n"
        if let handle = FileHandle(forWritingAtPath: dnsFile) {
            handle.seekToEndOfFile()
            handle.write(entry.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? entry.write(toFile: dnsFile, atomically: true, encoding: .utf8)
        }
    }

    public static func loadAll() -> [DNSRule] {
        guard let content = try? String(contentsOfFile: dnsFile, encoding: .utf8) else { return [] }
        return content.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { return nil }
            return DNSRule(domain: parts[0], ip: parts[1])
        }
    }

    public static func resolve(_ host: String) -> String? {
        let lowerHost = host.lowercased()
        for rule in loadAll() {
            if rule.domain.lowercased() == lowerHost {
                return rule.ip
            }
        }
        return nil
    }

    public static func clear() {
        try? "".write(toFile: dnsFile, atomically: true, encoding: .utf8)
    }
}

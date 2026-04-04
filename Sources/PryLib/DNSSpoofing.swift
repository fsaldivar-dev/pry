import Foundation

public struct DNSSpoofing {
    public static let dnsFile = "/tmp/pry.dns"

    public struct DNSRule {
        public let domain: String
        public let ip: String
    }

    public static func add(domain: String, ip: String) {
        let d = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\t", with: "").replacingOccurrences(of: "\n", with: "")
        let i = ip.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\t", with: "").replacingOccurrences(of: "\n", with: "")
        guard !d.isEmpty, !i.isEmpty else { return }
        let entry = "\(d)\t\(i)\n"
        if let data = entry.data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: dnsFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? entry.write(toFile: dnsFile, atomically: true, encoding: .utf8)
            }
        }
    }

    public static func loadAll() -> [DNSRule] {
        guard let content = try? String(contentsOfFile: dnsFile, encoding: .utf8) else { return [] }
        return content.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            return DNSRule(domain: parts[0], ip: parts[1])
        }
    }

    public static func resolve(_ host: String) -> String? {
        let h = host.lowercased()
        for rule in loadAll() {
            if h == rule.domain { return rule.ip }
        }
        return nil
    }

    public static func clear() {
        try? "".write(toFile: dnsFile, atomically: true, encoding: .utf8)
    }
}

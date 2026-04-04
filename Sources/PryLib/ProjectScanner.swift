import Foundation

/// Scans a project directory for API domains to populate .prywatch
public struct ProjectScanner {

    /// Common SDK/system domains to exclude from watchlist
    private static let excludedDomains: Set<String> = [
        "apple.com", "icloud.com", "mzstatic.com",
        "googleapis.com", "google.com", "gstatic.com",
        "facebook.com", "fbcdn.net",
        "crashlytics.com", "firebaseio.com",
        "sentry.io", "amplitude.com", "mixpanel.com",
        "localhost", "127.0.0.1", "example.com",
    ]

    /// File extensions to scan for domain references
    private static let sourceExtensions: Set<String> = ["swift", "m", "mm", "h", "plist"]

    /// Regex to match URLs and domains in source code
    private static let urlPattern = try! NSRegularExpression(
        pattern: #"https?://([a-zA-Z0-9][-a-zA-Z0-9]*(?:\.[a-zA-Z0-9][-a-zA-Z0-9]*)+)"#,
        options: []
    )

    /// Regex to match NSExceptionDomains keys in plist XML
    private static let plistDomainPattern = try! NSRegularExpression(
        pattern: #"<key>([a-zA-Z0-9][-a-zA-Z0-9]*(?:\.[a-zA-Z0-9][-a-zA-Z0-9]*)+)</key>"#,
        options: []
    )

    /// Scan directory and return discovered domains
    public static func scan(directory: String) -> [String] {
        var domains = Set<String>()
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(atPath: directory) else {
            return []
        }

        while let relativePath = enumerator.nextObject() as? String {
            // Skip build directories and hidden files
            if relativePath.hasPrefix(".") || relativePath.contains("/.") ||
               relativePath.contains("Pods/") || relativePath.contains(".build/") ||
               relativePath.contains("DerivedData/") || relativePath.contains("Carthage/") {
                continue
            }

            let ext = (relativePath as NSString).pathExtension.lowercased()
            guard sourceExtensions.contains(ext) else { continue }

            let fullPath = (directory as NSString).appendingPathComponent(relativePath)
            guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }

            // Extract domains from URLs
            let range = NSRange(content.startIndex..., in: content)

            let urlMatches = urlPattern.matches(in: content, options: [], range: range)
            for match in urlMatches {
                if let domainRange = Range(match.range(at: 1), in: content) {
                    let domain = String(content[domainRange]).lowercased()
                    domains.insert(domain)
                }
            }

            // For plist files, also check NSExceptionDomains
            if ext == "plist" {
                let plistMatches = plistDomainPattern.matches(in: content, options: [], range: range)
                for match in plistMatches {
                    if let domainRange = Range(match.range(at: 1), in: content) {
                        let domain = String(content[domainRange]).lowercased()
                        domains.insert(domain)
                    }
                }
            }
        }

        // Filter out SDK/system domains
        let filtered = domains.filter { domain in
            !excludedDomains.contains(where: { domain == $0 || domain.hasSuffix(".\($0)") })
        }

        return filtered.sorted()
    }
}

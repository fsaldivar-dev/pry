import Foundation
import NIOHTTP1

struct AppIdentifier {
    struct AppInfo {
        let icon: String
        let name: String
        let version: String?
    }

    static func identify(from headers: HTTPHeaders) -> AppInfo {
        guard let ua = headers["User-Agent"].first else {
            return AppInfo(icon: "❓", name: "Unknown", version: nil)
        }
        return parse(userAgent: ua)
    }

    static func parse(userAgent ua: String) -> AppInfo {
        // Safari on iOS
        if ua.contains("Safari/") && ua.contains("Mobile/") && ua.contains("iPhone") {
            let version = extractVersion(from: ua, after: "Version/")
            return AppInfo(icon: "🧭", name: "Safari", version: version)
        }

        // Safari on Mac
        if ua.contains("Safari/") && ua.contains("Macintosh") {
            let version = extractVersion(from: ua, after: "Version/")
            return AppInfo(icon: "🧭", name: "Safari macOS", version: version)
        }

        // Chrome
        if ua.contains("Chrome/") {
            let version = extractVersion(from: ua, after: "Chrome/")
            return AppInfo(icon: "🌐", name: "Chrome", version: version)
        }

        // Firefox
        if ua.contains("Firefox/") {
            let version = extractVersion(from: ua, after: "Firefox/")
            return AppInfo(icon: "🦊", name: "Firefox", version: version)
        }

        // curl
        if ua.hasPrefix("curl/") {
            let version = extractVersion(from: ua, after: "curl/")
            return AppInfo(icon: "🖥️", name: "curl", version: version)
        }

        // Python requests
        if ua.hasPrefix("python-requests/") {
            let version = extractVersion(from: ua, after: "python-requests/")
            return AppInfo(icon: "🐍", name: "Python", version: version)
        }

        // Xcode
        if ua.contains("Xcode") {
            return AppInfo(icon: "🔨", name: "Xcode", version: nil)
        }

        // iOS app with CFNetwork (AppName/Version CFNetwork/X Darwin/Y)
        if ua.contains("CFNetwork/") {
            let parts = ua.split(separator: " ")
            if let first = parts.first, first.contains("/") {
                let appParts = first.split(separator: "/")
                let name = String(appParts[0])
                let version = appParts.count > 1 ? String(appParts[1]) : nil
                return AppInfo(icon: "📱", name: name, version: version)
            }
            return AppInfo(icon: "📱", name: "iOS App", version: nil)
        }

        // WKWebView (has Mobile/ but not Safari/)
        if ua.contains("Mobile/") && !ua.contains("Safari/") {
            return AppInfo(icon: "📱", name: "WebView", version: nil)
        }

        // Generic with AppName/Version pattern
        let parts = ua.split(separator: " ")
        if let first = parts.first, first.contains("/") {
            let appParts = first.split(separator: "/")
            let name = String(appParts[0])
            let version = appParts.count > 1 ? String(appParts[1]) : nil
            return AppInfo(icon: "🔧", name: name, version: version)
        }

        return AppInfo(icon: "❓", name: String(ua.prefix(20)), version: nil)
    }

    static func label(from headers: HTTPHeaders) -> String {
        let app = identify(from: headers)
        let ver = app.version.map { "/\($0)" } ?? ""
        return "\(app.icon) \(app.name)\(ver)"
    }

    private static func extractVersion(from ua: String, after prefix: String) -> String? {
        guard let range = ua.range(of: prefix) else { return nil }
        let rest = ua[range.upperBound...]
        let version = rest.prefix(while: { $0 != " " && $0 != ")" && $0 != ";" })
        return version.isEmpty ? nil : String(version)
    }
}

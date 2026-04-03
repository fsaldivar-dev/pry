import Foundation

public struct CurlGenerator {
    public static func generate(from req: RequestStore.CapturedRequest, https: Bool = false) -> String {
        var parts: [String] = ["curl"]

        // Method (skip for GET since it's default)
        if req.method != "GET" {
            parts.append("-X \(req.method)")
        }

        // URL
        let scheme = https ? "https" : "http"
        let url = "\(scheme)://\(req.host)\(req.url)"
        parts.append("'\(url)'")

        // Headers
        for (name, value) in req.requestHeaders {
            let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-H '\(name): \(escaped)'")
        }

        // Body
        if let body = req.requestBody, !body.isEmpty {
            let escaped = body.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-d '\(escaped)'")
        }

        return parts.joined(separator: " \\\n  ")
    }

    /// Copy to macOS clipboard via pbcopy
    public static func copyToClipboard(_ text: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        let pipe = Pipe()
        process.standardInput = pipe
        do {
            try process.run()
            pipe.fileHandleForWriting.write(text.data(using: .utf8)!)
            pipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

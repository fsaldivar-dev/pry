import Foundation
import NIOCore

struct BodyPrinter {
    static let maxBodyPreview = 2000

    static func printRequestHead(_ head: HTTPRequestHead, host: String, port: Int) {
        let method = "\(head.method)"
        let url = head.uri
        let appLabel = AppIdentifier.label(from: head.headers)
        print(colored(appLabel, .bold) + " " + request(">>> \(method) \(url)") + " " + tunnel("-> \(host):\(port)"))

        // Show key request headers (skip User-Agent since it's in the app label)
        let interestingHeaders = ["Content-Type", "Authorization", "Accept"]
        for name in interestingHeaders {
            if let value = head.headers[name].first {
                print(colored("    \(name): \(value)", .dim))
            }
        }
    }

    static func printRequestBody(_ body: ByteBuffer?) {
        guard let body = body, body.readableBytes > 0 else { return }
        var buf = body
        if let text = buf.readString(length: min(buf.readableBytes, maxBodyPreview)) {
            let formatted = formatBody(text, contentType: nil)
            print(colored("    Body: ", .dim) + formatted)
        }
    }

    static func printResponseHead(_ head: HTTPResponseHead, host: String, https: Bool = false) {
        let scheme = https ? "https" : "http"
        let statusColor = head.status.code < 400
            ? response("<<< \(head.status.code) \(head.status.reasonPhrase ?? "")")
            : errText("<<< \(head.status.code) \(head.status.reasonPhrase ?? "")")
        print("\(statusColor) " + tunnel("\(scheme)://\(host)"))

        // Show key response headers
        let interestingHeaders = ["Content-Type", "Content-Length", "Location", "Set-Cookie"]
        for name in interestingHeaders {
            if let value = head.headers[name].first {
                print(colored("    \(name): \(value)", .dim))
            }
        }
    }

    static func printResponseBody(_ buffer: ByteBuffer, contentType: String?) {
        var buf = buffer
        guard buf.readableBytes > 0 else { return }
        guard shouldPrintBody(contentType: contentType) else {
            print(colored("    Body: [\(buf.readableBytes) bytes, \(contentType ?? "binary")]", .dim))
            return
        }
        if let text = buf.readString(length: min(buf.readableBytes, maxBodyPreview)) {
            let formatted = formatBody(text, contentType: contentType)
            let truncated = buf.readableBytes > maxBodyPreview ? colored(" ...(truncated)", .dim) : ""
            print(colored("    Body: ", .dim) + formatted + truncated)
        }
    }

    static func printMock(path: String, json: String) {
        print(mock("<<< MOCK \(path) (200 OK)"))
        let formatted = formatBody(json, contentType: "application/json")
        print(colored("    Body: ", .dim) + formatted)
    }

    private static func shouldPrintBody(contentType: String?) -> Bool {
        guard let ct = contentType?.lowercased() else { return true }
        if ct.contains("json") || ct.contains("text") || ct.contains("xml") || ct.contains("html") || ct.contains("javascript") {
            return true
        }
        return false
    }

    private static func formatBody(_ text: String, contentType: String?) -> String {
        // Try to pretty-print JSON
        if let ct = contentType, ct.contains("json"), let data = text.data(using: .utf8) {
            return prettyJSON(data) ?? text
        }
        // Auto-detect JSON even without content-type
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")), let data = text.data(using: .utf8) {
            return prettyJSON(data) ?? text
        }
        // Truncate long non-JSON text
        if text.count > 200 {
            return String(text.prefix(200)) + "..."
        }
        return text
    }

    private static func prettyJSON(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else {
            return nil
        }
        // Indent each line for alignment
        let lines = str.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 1 {
            return lines.enumerated().map { i, line in
                i == 0 ? String(line) : "          \(line)"
            }.joined(separator: "\n")
        }
        return str
    }
}

// Re-export HTTPRequestHead for convenience
import NIOHTTP1
typealias HTTPRequestHead = NIOHTTP1.HTTPRequestHead
typealias HTTPResponseHead = NIOHTTP1.HTTPResponseHead

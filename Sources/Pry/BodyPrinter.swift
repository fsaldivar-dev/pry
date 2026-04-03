import Foundation
import NIOCore

struct BodyPrinter {
    static let maxBodyPreview = 2000
    private static let out = OutputBroker.shared

    @discardableResult
    static func printRequestHead(_ head: HTTPRequestHead, host: String, port: Int) -> Int {
        let method = "\(head.method)"
        let url = head.uri
        let app = AppIdentifier.identify(from: head.headers)
        out.log(colored("\(app.icon) \(app.name)", .bold) + " " + request(">>> \(method) \(url)") + " " + tunnel("-> \(host):\(port)"), type: .request)

        var headers: [(String, String)] = []
        let interestingHeaders = ["Content-Type", "Authorization", "Accept", "User-Agent"]
        for name in interestingHeaders {
            if let value = head.headers[name].first {
                headers.append((name, value))
                if name != "User-Agent" {
                    out.log(colored("    \(name): \(value)", .dim), type: .info)
                }
            }
        }

        // Store in RequestStore for TUI navigation
        return RequestStore.shared.addRequest(
            method: method, url: url, host: host,
            appIcon: app.icon, appName: app.name + (app.version.map { "/\($0)" } ?? ""),
            headers: headers, body: nil
        )
    }

    static func printRequestBody(_ body: ByteBuffer?) {
        guard let body = body, body.readableBytes > 0 else { return }
        var buf = body
        if let text = buf.readString(length: min(buf.readableBytes, maxBodyPreview)) {
            let formatted = formatBody(text, contentType: nil)
            out.log(colored("    Body: ", .dim) + formatted, type: .info)
        }
    }

    static func printResponseHead(_ head: HTTPResponseHead, host: String, https: Bool = false) {
        let scheme = https ? "https" : "http"
        let statusColor = head.status.code < 400
            ? response("<<< \(head.status.code) \(head.status.reasonPhrase ?? "")")
            : errText("<<< \(head.status.code) \(head.status.reasonPhrase ?? "")")
        let type: OutputBroker.EntryType = head.status.code < 400 ? .response : .error
        out.log("\(statusColor) " + tunnel("\(scheme)://\(host)"), type: type)

        let interestingHeaders = ["Content-Type", "Content-Length", "Location", "Set-Cookie"]
        for name in interestingHeaders {
            if let value = head.headers[name].first {
                out.log(colored("    \(name): \(value)", .dim), type: .info)
            }
        }
    }

    static func printResponseBody(_ buffer: ByteBuffer, contentType: String?) {
        var buf = buffer
        guard buf.readableBytes > 0 else { return }
        guard shouldPrintBody(contentType: contentType) else {
            out.log(colored("    Body: [\(buf.readableBytes) bytes, \(contentType ?? "binary")]", .dim), type: .info)
            return
        }
        if let text = buf.readString(length: min(buf.readableBytes, maxBodyPreview)) {
            let formatted = formatBody(text, contentType: contentType)
            let truncated = buf.readableBytes > maxBodyPreview ? colored(" ...(truncated)", .dim) : ""
            out.log(colored("    Body: ", .dim) + formatted + truncated, type: .info)
        }
    }

    static func storeResponse(requestId: Int, statusCode: UInt, headers: [(String, String)], body: String?, isMock: Bool = false) {
        RequestStore.shared.updateResponse(id: requestId, statusCode: statusCode, headers: headers, body: body, isMock: isMock)
    }

    static func storeTunnel(host: String) {
        RequestStore.shared.addTunnel(host: host)
    }

    static func printMock(path: String, json: String) {
        out.log(mock("<<< MOCK \(path) (200 OK)"), type: .mock)
        let formatted = formatBody(json, contentType: "application/json")
        out.log(colored("    Body: ", .dim) + formatted, type: .info)
    }

    private static func shouldPrintBody(contentType: String?) -> Bool {
        guard let ct = contentType?.lowercased() else { return true }
        return ct.contains("json") || ct.contains("text") || ct.contains("xml") || ct.contains("html") || ct.contains("javascript")
    }

    private static func formatBody(_ text: String, contentType: String?) -> String {
        if let ct = contentType, ct.contains("json"), let data = text.data(using: .utf8) {
            return prettyJSON(data) ?? text
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")), let data = text.data(using: .utf8) {
            return prettyJSON(data) ?? text
        }
        if text.count > 200 {
            return String(text.prefix(200)) + "..."
        }
        return text
    }

    private static func prettyJSON(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else { return nil }
        let lines = str.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 1 {
            return lines.enumerated().map { i, line in
                i == 0 ? String(line) : "          \(line)"
            }.joined(separator: "\n")
        }
        return str
    }
}

import NIOHTTP1
typealias HTTPRequestHead = NIOHTTP1.HTTPRequestHead
typealias HTTPResponseHead = NIOHTTP1.HTTPResponseHead

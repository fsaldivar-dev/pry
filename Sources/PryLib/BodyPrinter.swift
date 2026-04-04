import Foundation
import NIOCore

public struct BodyPrinter {
    public static let maxBodyPreview = 2000
    private static let out = OutputBroker.shared

    @discardableResult
    public static func printRequestHead(_ head: HTTPRequestHead, host: String, port: Int) -> Int {
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

    public static func printRequestBody(_ body: ByteBuffer?, requestId: Int = 0) {
        guard let body = body, body.readableBytes > 0 else { return }
        var buf = body
        if let text = buf.readString(length: min(buf.readableBytes, maxBodyPreview)) {
            let formatted = formatBody(text, contentType: nil)
            out.log(colored("    Body: ", .dim) + formatted, type: .info)

            // Detect GraphQL
            if requestId > 0, let gql = GraphQLDetector.detect(body: text) {
                let opName = gql.operationName ?? "anonymous"
                out.log(colored("    🔮 GraphQL: \(opName)", .bold), type: .info)
                RequestStore.shared.setGraphQLOperation(id: requestId, operation: opName)
            }
        }
    }

    public static func printResponseHead(_ head: HTTPResponseHead, host: String, https: Bool = false) {
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

    public static func printResponseBody(_ buffer: ByteBuffer, contentType: String?) {
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

    public static func storeResponse(requestId: Int, statusCode: UInt, headers: [(String, String)], body: String?, isMock: Bool = false) {
        RequestStore.shared.updateResponse(id: requestId, statusCode: statusCode, headers: headers, body: body, isMock: isMock)
    }

    public static func storeTunnel(host: String) {
        RequestStore.shared.addTunnel(host: host)
    }

    public static func printMock(path: String, json: String) {
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
        let colorized = colorizeJSON(str)
        let lines = colorized.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 1 {
            return lines.enumerated().map { i, line in
                i == 0 ? String(line) : "          \(line)"
            }.joined(separator: "\n")
        }
        return colorized
    }

    public static func colorizeJSON(_ json: String) -> String {
        var result = ""
        var inString = false
        var isKey = true
        var escaped = false
        var i = json.startIndex

        while i < json.endIndex {
            let c = json[i]

            if escaped {
                result.append(c)
                escaped = false
                i = json.index(after: i)
                continue
            }

            if c == "\\" && inString {
                escaped = true
                result.append(c)
                i = json.index(after: i)
                continue
            }

            if c == "\"" {
                if !inString {
                    inString = true
                    let color = isKey ? "\u{001B}[36m" : "\u{001B}[32m"
                    result += color + "\""
                } else {
                    inString = false
                    result += "\"\u{001B}[0m"
                }
            } else if inString {
                result.append(c)
            } else if c == ":" {
                isKey = false
                result.append(c)
            } else if c == "," || c == "{" || c == "[" {
                isKey = (c == "," || c == "{")
                result.append(c)
            } else if c.isNumber || c == "-" {
                result += "\u{001B}[33m"
                result.append(c)
                var next = json.index(after: i)
                while next < json.endIndex {
                    let nc = json[next]
                    if nc.isNumber || nc == "." || nc == "e" || nc == "E" || nc == "+" || nc == "-" {
                        result.append(nc)
                        next = json.index(after: next)
                    } else { break }
                }
                result += "\u{001B}[0m"
                i = next
                continue
            } else if json[i...].hasPrefix("true") {
                result += "\u{001B}[34mtrue\u{001B}[0m"
                i = json.index(i, offsetBy: 4)
                continue
            } else if json[i...].hasPrefix("false") {
                result += "\u{001B}[34mfalse\u{001B}[0m"
                i = json.index(i, offsetBy: 5)
                continue
            } else if json[i...].hasPrefix("null") {
                result += "\u{001B}[90mnull\u{001B}[0m"
                i = json.index(i, offsetBy: 4)
                continue
            } else {
                result.append(c)
            }
            i = json.index(after: i)
        }
        return result
    }
}

import NIOHTTP1
public typealias HTTPRequestHead = NIOHTTP1.HTTPRequestHead
public typealias HTTPResponseHead = NIOHTTP1.HTTPResponseHead

import Foundation

public struct DiffTool {
    public enum DiffLine {
        case same(String)
        case added(String)
        case removed(String)
        case changed(label: String, left: String, right: String)
    }

    public static func diff(req1: RequestStore.CapturedRequest, req2: RequestStore.CapturedRequest) -> [DiffLine] {
        var lines: [DiffLine] = []

        // Method
        if req1.method == req2.method { lines.append(.same("Method: \(req1.method)")) }
        else { lines.append(.changed(label: "Method", left: req1.method, right: req2.method)) }

        // URL
        if req1.url == req2.url { lines.append(.same("URL: \(req1.url)")) }
        else { lines.append(.changed(label: "URL", left: req1.url, right: req2.url)) }

        // Host
        if req1.host != req2.host {
            lines.append(.changed(label: "Host", left: req1.host, right: req2.host))
        }

        // Headers diff
        let h1 = Dictionary(req1.requestHeaders, uniquingKeysWith: { $1 })
        let h2 = Dictionary(req2.requestHeaders, uniquingKeysWith: { $1 })
        let allKeys = Set(h1.keys).union(h2.keys).sorted()
        for key in allKeys {
            switch (h1[key], h2[key]) {
            case (.some(let v1), .some(let v2)) where v1 != v2:
                lines.append(.changed(label: key, left: v1, right: v2))
            case (.some(let v), nil):
                lines.append(.removed("\(key): \(v)"))
            case (nil, .some(let v)):
                lines.append(.added("\(key): \(v)"))
            default: break
            }
        }

        // Body diff
        if req1.requestBody != req2.requestBody {
            if let b1 = req1.requestBody { lines.append(.removed("Body: \(b1.prefix(200))")) }
            if let b2 = req2.requestBody { lines.append(.added("Body: \(b2.prefix(200))")) }
        }

        // Status
        if req1.statusCode != req2.statusCode {
            lines.append(.changed(label: "Status",
                left: req1.statusCode.map { "\($0)" } ?? "N/A",
                right: req2.statusCode.map { "\($0)" } ?? "N/A"))
        }

        // Response body diff
        if req1.responseBody != req2.responseBody {
            if let b1 = req1.responseBody { lines.append(.removed("Response: \(b1.prefix(200))")) }
            if let b2 = req2.responseBody { lines.append(.added("Response: \(b2.prefix(200))")) }
        }

        return lines
    }

    public static func format(_ lines: [DiffLine]) -> String {
        lines.map { line in
            switch line {
            case .same(let text): return "  \(text)"
            case .added(let text): return colored("+ \(text)", .green)
            case .removed(let text): return colored("- \(text)", .red)
            case .changed(let label, let left, let right):
                return colored("- \(label): \(left)", .red) + "\n" + colored("+ \(label): \(right)", .green)
            }
        }.joined(separator: "\n")
    }
}

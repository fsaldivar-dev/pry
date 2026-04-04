import Foundation

public struct SwiftGenerator {
    private static func escapeSwiftString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
    }

    public static func generate(from req: RequestStore.CapturedRequest, https: Bool = false) -> String {
        let scheme = https ? "https" : "http"
        let escapedURL = escapeSwiftString("\(scheme)://\(req.host)\(req.url)")
        var lines: [String] = []
        lines.append("let url = URL(string: \"\(escapedURL)\")!")
        lines.append("var request = URLRequest(url: url)")
        if req.method != "GET" {
            lines.append("request.httpMethod = \"\(escapeSwiftString(req.method))\"")
        }
        for (name, value) in req.requestHeaders {
            lines.append("request.setValue(\"\(escapeSwiftString(value))\", forHTTPHeaderField: \"\(escapeSwiftString(name))\")")
        }
        if let body = req.requestBody, !body.isEmpty {
            lines.append("request.httpBody = \"\(escapeSwiftString(body))\".data(using: .utf8)")
        }
        lines.append("")
        lines.append("let (data, response) = try await URLSession.shared.data(for: request)")
        return lines.joined(separator: "\n")
    }
}

public struct PythonGenerator {
    private static func escapePythonString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
    }

    public static func generate(from req: RequestStore.CapturedRequest, https: Bool = false) -> String {
        let scheme = https ? "https" : "http"
        let escapedURL = escapePythonString("\(scheme)://\(req.host)\(req.url)")
        var lines: [String] = ["import requests", ""]
        let method = req.method.lowercased()

        var headerParts: [String] = []
        for (name, value) in req.requestHeaders {
            headerParts.append("\"\(escapePythonString(name))\": \"\(escapePythonString(value))\"")
        }
        let headersDict = "{\(headerParts.joined(separator: ", "))}"

        if let body = req.requestBody, !body.isEmpty {
            let escapedBody = escapePythonString(body)
            lines.append("response = requests.\(method)(")
            lines.append("    \"\(escapedURL)\",")
            lines.append("    headers=\(headersDict),")
            lines.append("    data=\"\(escapedBody)\"")
            lines.append(")")
        } else {
            lines.append("response = requests.\(method)(\"\(escapedURL)\", headers=\(headersDict))")
        }
        lines.append("print(response.json())")
        return lines.joined(separator: "\n")
    }
}

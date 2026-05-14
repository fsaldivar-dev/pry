import Foundation

// MARK: - Sanitization helpers

/// Allowed HTTP methods for code generation
private let validHTTPMethods: Set<String> = [
    "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "TRACE", "CONNECT"
]

/// Sanitize a string for embedding inside a Swift double-quoted string literal
private func swiftStringEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
     .replacingOccurrences(of: "\"", with: "\\\"")
     .replacingOccurrences(of: "\n", with: "\\n")
     .replacingOccurrences(of: "\r", with: "\\r")
     .replacingOccurrences(of: "\t", with: "\\t")
}

/// Sanitize a string for embedding inside a Python double-quoted string literal
private func pythonStringEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
     .replacingOccurrences(of: "\"", with: "\\\"")
     .replacingOccurrences(of: "\n", with: "\\n")
     .replacingOccurrences(of: "\r", with: "\\r")
     .replacingOccurrences(of: "\t", with: "\\t")
}

/// Validate and normalize an HTTP method, returning uppercased form or "GET" if invalid
private func sanitizeMethod(_ method: String) -> String {
    let upper = method.uppercased()
    return validHTTPMethods.contains(upper) ? upper : "GET"
}

// MARK: - Swift Generator

/// Generates Swift URLSession code from a captured request
public struct SwiftGenerator {
    public static func generate(from req: RequestStore.CapturedRequest, https: Bool = false) -> String {
        let scheme = https ? "https" : "http"
        let escapedHost = swiftStringEscape(req.host)
        let escapedURL = swiftStringEscape(req.url)
        let url = "\(scheme)://\(escapedHost)\(escapedURL)"
        let method = sanitizeMethod(req.method)

        var lines: [String] = []
        lines.append("let url = URL(string: \"\(url)\")!")
        lines.append("var request = URLRequest(url: url)")

        // Method (skip for GET since it's default)
        if method != "GET" {
            lines.append("request.httpMethod = \"\(method)\"")
        }

        // Headers
        for (name, value) in req.requestHeaders {
            let escapedName = swiftStringEscape(name)
            let escapedValue = swiftStringEscape(value)
            lines.append("request.setValue(\"\(escapedValue)\", forHTTPHeaderField: \"\(escapedName)\")")
        }

        // Body
        if let body = req.requestBody, !body.isEmpty {
            let escaped = swiftStringEscape(body)
            lines.append("request.httpBody = \"\(escaped)\".data(using: .utf8)")
        }

        // URLSession call
        lines.append("")
        lines.append("let (data, response) = try await URLSession.shared.data(for: request)")
        lines.append("let httpResponse = response as! HTTPURLResponse")
        lines.append("print(httpResponse.statusCode)")

        return lines.joined(separator: "\n")
    }
}

// MARK: - Python Generator

/// Generates Python requests code from a captured request
public struct PythonGenerator {
    public static func generate(from req: RequestStore.CapturedRequest, https: Bool = false) -> String {
        let scheme = https ? "https" : "http"
        let escapedHost = pythonStringEscape(req.host)
        let escapedURL = pythonStringEscape(req.url)
        let url = "\(scheme)://\(escapedHost)\(escapedURL)"
        let method = sanitizeMethod(req.method)
        let methodLower = method.lowercased()

        var lines: [String] = []
        lines.append("import requests")
        lines.append("import json")
        lines.append("")

        // Headers
        if !req.requestHeaders.isEmpty {
            lines.append("headers = {")
            for (name, value) in req.requestHeaders {
                let escapedName = pythonStringEscape(name)
                let escapedValue = pythonStringEscape(value)
                lines.append("    \"\(escapedName)\": \"\(escapedValue)\",")
            }
            lines.append("}")
            lines.append("")
        }

        // Body — use json.loads() to produce a proper Python dict for the json= parameter
        if let body = req.requestBody, !body.isEmpty {
            let trimmed = body.trimmingCharacters(in: .whitespaces)
            let isJSON = trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
            let escapedBody = pythonStringEscape(body)

            if isJSON {
                lines.append("body = json.loads(\"\(escapedBody)\")")
            } else {
                lines.append("body = \"\(escapedBody)\"")
            }
            lines.append("")
        }

        // Build the call
        var callParts: [String] = ["\"\(url)\""]

        if !req.requestHeaders.isEmpty {
            callParts.append("headers=headers")
        }

        if let body = req.requestBody, !body.isEmpty {
            let trimmed = body.trimmingCharacters(in: .whitespaces)
            let isJSON = trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
            callParts.append(isJSON ? "json=body" : "data=body")
        }

        lines.append("response = requests.\(methodLower)(\(callParts.joined(separator: ", ")))")
        lines.append("print(response.status_code)")
        lines.append("print(response.text)")

        return lines.joined(separator: "\n")
    }
}

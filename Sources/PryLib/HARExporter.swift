import Foundation

public struct HARExporter {
    public static func export(from store: RequestStore) -> String {
        let entries = store.getAll()
        let iso = ISO8601DateFormatter()

        var harEntries: [[String: Any]] = []

        for req in entries {
            if req.isTunnel { continue }

            // Request
            let requestHeaders = req.requestHeaders.map { ["name": $0.0, "value": $0.1] }
            let scheme = req.statusCode != nil ? "http" : "http"  // simplified
            let requestObj: [String: Any] = [
                "method": req.method,
                "url": "\(scheme)://\(req.host)\(req.url)",
                "httpVersion": "HTTP/1.1",
                "headers": requestHeaders,
                "queryString": [] as [[String: String]],
                "headersSize": -1,
                "bodySize": req.requestBody?.count ?? 0,
                "postData": req.requestBody.map { ["mimeType": "application/json", "text": $0] } as Any
            ]

            // Response
            let responseHeaders = req.responseHeaders.map { ["name": $0.0, "value": $0.1] }
            let responseObj: [String: Any] = [
                "status": Int(req.statusCode ?? 0),
                "statusText": statusText(for: req.statusCode ?? 0),
                "httpVersion": "HTTP/1.1",
                "headers": responseHeaders,
                "content": [
                    "size": req.responseBody?.count ?? 0,
                    "mimeType": "application/json",
                    "text": req.responseBody ?? ""
                ] as [String: Any],
                "headersSize": -1,
                "bodySize": req.responseBody?.count ?? 0,
                "redirectURL": ""
            ]

            let entry: [String: Any] = [
                "startedDateTime": iso.string(from: req.timestamp),
                "time": 0,
                "request": requestObj,
                "response": responseObj,
                "cache": [:] as [String: Any],
                "timings": ["send": 0, "wait": 0, "receive": 0] as [String: Any]
            ]

            harEntries.append(entry)
        }

        let har: [String: Any] = [
            "log": [
                "version": "1.2",
                "creator": [
                    "name": "Pry",
                    "version": "0.2"
                ] as [String: Any],
                "entries": harEntries
            ] as [String: Any]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: har, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"log\":{\"version\":\"1.2\",\"creator\":{\"name\":\"Pry\"},\"entries\":[]}}"
        }
        return json
    }

    public static func exportToFile(from store: RequestStore, path: String) throws {
        let har = export(from: store)
        try har.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func statusText(for code: UInt) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return ""
        }
    }
}

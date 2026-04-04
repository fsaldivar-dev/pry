import Foundation

public struct HARImporter {
    public static func importFromFile(path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let log = json["log"] as? [String: Any],
              let entries = log["entries"] as? [[String: Any]] else {
            throw HARImportError.invalidFormat
        }

        var requests: [RequestStore.CapturedRequest] = []
        for entry in entries {
            guard let reqObj = entry["request"] as? [String: Any],
                  let method = reqObj["method"] as? String,
                  let url = reqObj["url"] as? String else { continue }

            // Parse URL for host and path
            let components = URLComponents(string: url)
            let host = components?.host ?? "unknown"
            let path = components?.path ?? url

            // Parse request headers
            let reqHeaders: [(String, String)] = (reqObj["headers"] as? [[String: String]])?.compactMap { h -> (String, String)? in
                guard let name = h["name"], let value = h["value"] else { return nil }
                return (name, value)
            } ?? []

            // Parse request body
            let postData = reqObj["postData"] as? [String: Any]
            let requestBody = postData?["text"] as? String

            // Parse response
            let respObj = entry["response"] as? [String: Any]
            let statusCode = (respObj?["status"] as? Int).map { UInt($0) }
            let content = respObj?["content"] as? [String: Any]
            let responseBody = content?["text"] as? String

            let respHeaders: [(String, String)] = (respObj?["headers"] as? [[String: String]])?.compactMap { h -> (String, String)? in
                guard let name = h["name"], let value = h["value"] else { return nil }
                return (name, value)
            } ?? []

            let request = RequestStore.CapturedRequest(
                method: method,
                url: path,
                host: host,
                appIcon: "📥",
                appName: "import",
                requestHeaders: reqHeaders,
                requestBody: requestBody,
                statusCode: statusCode,
                responseHeaders: respHeaders,
                responseBody: responseBody
            )
            requests.append(request)
        }

        RequestStore.shared.loadEntries(requests)
    }

    public enum HARImportError: Error {
        case invalidFormat
    }
}

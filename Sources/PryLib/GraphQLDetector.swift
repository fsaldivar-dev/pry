import Foundation

public struct GraphQLInfo {
    public let operationName: String?
    public let query: String
    public let variables: String?
}

public struct GraphQLDetector {
    /// Detect if a request body contains a GraphQL query
    public static func detect(body: String?) -> GraphQLInfo? {
        guard let body = body,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = json["query"] as? String else {
            return nil
        }
        let operationName = json["operationName"] as? String
        var variables: String?
        if let vars = json["variables"] {
            if let varsData = try? JSONSerialization.data(withJSONObject: vars),
               let varsStr = String(data: varsData, encoding: .utf8) {
                variables = varsStr
            }
        }
        return GraphQLInfo(operationName: operationName, query: query, variables: variables)
    }

    /// Format GraphQL info for display
    public static func formatQuery(_ info: GraphQLInfo) -> String {
        var parts: [String] = []
        if let name = info.operationName {
            parts.append("Operation: \(name)")
        }
        parts.append("Query: \(info.query.prefix(200))")
        if let vars = info.variables {
            parts.append("Variables: \(vars.prefix(100))")
        }
        return parts.joined(separator: "\n")
    }
}

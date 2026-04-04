import Foundation

/// MCP (Model Context Protocol) server for Claude Code integration.
/// Exposes Pry captured traffic as tools via JSON-RPC 2.0 over stdio.
public struct MCPServer {
    /// Handle a single JSON-RPC request and return the response
    public static func handleRequest(_ input: String) -> String {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String,
              let id = json["id"] else {
            return jsonRPCError(id: nil, code: -32700, message: "Parse error")
        }

        switch method {
        case "initialize":
            return jsonRPCResult(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "pry", "version": "0.5"]
            ])
        case "tools/list":
            return jsonRPCResult(id: id, result: ["tools": toolDefinitions()])
        case "tools/call":
            return handleToolCall(json: json, id: id)
        default:
            return jsonRPCError(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    /// Run MCP server loop reading from stdin
    public static func run() {
        while let line = readLine() {
            let response = handleRequest(line)
            print(response)
            fflush(stdout)
        }
    }

    // MARK: - Tools

    private static func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "list_requests",
                "description": "List all captured HTTP requests with method, URL, status, and host",
                "inputSchema": ["type": "object", "properties": [:] as [String: Any]]
            ],
            [
                "name": "get_request",
                "description": "Get full details of a captured request by ID",
                "inputSchema": ["type": "object", "properties": ["id": ["type": "number", "description": "Request ID"]], "required": ["id"]]
            ],
            [
                "name": "search_requests",
                "description": "Search captured requests by URL, host, or body content",
                "inputSchema": ["type": "object", "properties": ["query": ["type": "string", "description": "Search text"]], "required": ["query"]]
            ],
            [
                "name": "export_curl",
                "description": "Generate a curl command for a captured request by ID",
                "inputSchema": ["type": "object", "properties": ["id": ["type": "number", "description": "Request ID"]], "required": ["id"]]
            ]
        ]
    }

    private static func handleToolCall(json: [String: Any], id: Any) -> String {
        guard let params = json["params"] as? [String: Any],
              let toolName = params["name"] as? String else {
            return jsonRPCError(id: id, code: -32602, message: "Invalid params")
        }
        let args = params["arguments"] as? [String: Any] ?? [:]

        switch toolName {
        case "list_requests":
            let requests = RequestStore.shared.getAll()
            let list = requests.map { req -> [String: Any] in
                ["id": req.id, "method": req.method, "url": req.url, "host": req.host,
                 "statusCode": req.statusCode as Any, "timestamp": ISO8601DateFormatter().string(from: req.timestamp)]
            }
            return jsonRPCResult(id: id, result: ["content": [["type": "text", "text": toJSON(list)]]])

        case "get_request":
            guard let reqId = args["id"] as? Int ?? (args["id"] as? Double).map({ Int($0) }),
                  let req = RequestStore.shared.get(id: reqId) else {
                return jsonRPCResult(id: id, result: ["content": [["type": "text", "text": "Request not found"]]])
            }
            let detail: [String: Any] = [
                "id": req.id, "method": req.method, "url": req.url, "host": req.host,
                "requestHeaders": req.requestHeaders.map { ["name": $0.0, "value": $0.1] },
                "requestBody": req.requestBody as Any,
                "statusCode": req.statusCode as Any,
                "responseHeaders": req.responseHeaders.map { ["name": $0.0, "value": $0.1] },
                "responseBody": req.responseBody as Any
            ]
            return jsonRPCResult(id: id, result: ["content": [["type": "text", "text": toJSON(detail)]]])

        case "search_requests":
            guard let query = args["query"] as? String else {
                return jsonRPCError(id: id, code: -32602, message: "Missing query parameter")
            }
            let results = RequestStore.shared.search(query)
            let list = results.map { req -> [String: Any] in
                ["id": req.id, "method": req.method, "url": req.url, "host": req.host,
                 "statusCode": req.statusCode as Any]
            }
            return jsonRPCResult(id: id, result: ["content": [["type": "text", "text": toJSON(list)]]])

        case "export_curl":
            guard let reqId = args["id"] as? Int ?? (args["id"] as? Double).map({ Int($0) }),
                  let req = RequestStore.shared.get(id: reqId) else {
                return jsonRPCResult(id: id, result: ["content": [["type": "text", "text": "Request not found"]]])
            }
            let curl = CurlGenerator.generate(from: req, https: Watchlist.matches(req.host))
            return jsonRPCResult(id: id, result: ["content": [["type": "text", "text": curl]]])

        default:
            return jsonRPCError(id: id, code: -32602, message: "Unknown tool: \(toolName)")
        }
    }

    // MARK: - JSON-RPC helpers

    private static func jsonRPCResult(id: Any, result: [String: Any]) -> String {
        let response: [String: Any] = ["jsonrpc": "2.0", "id": id, "result": result]
        return toJSON(response)
    }

    private static func jsonRPCError(id: Any?, code: Int, message: String) -> String {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": ["code": code, "message": message]
        ]
        return toJSON(response)
    }

    private static func toJSON(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}

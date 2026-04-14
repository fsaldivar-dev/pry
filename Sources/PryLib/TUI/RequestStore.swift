import Foundation

/// Stores captured requests for TUI navigation
public class RequestStore {
    public static let shared = RequestStore()

    private let queue = DispatchQueue(label: "pry.requeststore")
    private var entries: [CapturedRequest] = []
    private let maxEntries = 500
    public var onChange: (() -> Void)?

    private struct CodableHeader: Codable {
        let name: String
        let value: String
    }

    public struct CapturedRequest: Codable {
        enum CodingKeys: String, CodingKey {
            case id, timestamp, method, url, host, appIcon, appName
            case requestHeaders, requestBody, statusCode
            case responseHeaders, responseBody
            case isMock, isTunnel, isPinned, isWebSocket, graphqlOperation, mockSource
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(timestamp, forKey: .timestamp)
            try c.encode(method, forKey: .method)
            try c.encode(url, forKey: .url)
            try c.encode(host, forKey: .host)
            try c.encode(appIcon, forKey: .appIcon)
            try c.encode(appName, forKey: .appName)
            try c.encode(requestHeaders.map { CodableHeader(name: $0.0, value: $0.1) }, forKey: .requestHeaders)
            try c.encode(requestBody, forKey: .requestBody)
            try c.encode(statusCode, forKey: .statusCode)
            try c.encode(responseHeaders.map { CodableHeader(name: $0.0, value: $0.1) }, forKey: .responseHeaders)
            try c.encode(responseBody, forKey: .responseBody)
            try c.encode(isMock, forKey: .isMock)
            try c.encode(isTunnel, forKey: .isTunnel)
            try c.encode(isPinned, forKey: .isPinned)
            try c.encode(isWebSocket, forKey: .isWebSocket)
            try c.encodeIfPresent(graphqlOperation, forKey: .graphqlOperation)
            try c.encodeIfPresent(mockSource, forKey: .mockSource)
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id)
            timestamp = try c.decode(Date.self, forKey: .timestamp)
            method = try c.decode(String.self, forKey: .method)
            url = try c.decode(String.self, forKey: .url)
            host = try c.decode(String.self, forKey: .host)
            appIcon = try c.decode(String.self, forKey: .appIcon)
            appName = try c.decode(String.self, forKey: .appName)
            requestHeaders = try c.decode([CodableHeader].self, forKey: .requestHeaders).map { ($0.name, $0.value) }
            requestBody = try c.decodeIfPresent(String.self, forKey: .requestBody)
            statusCode = try c.decodeIfPresent(UInt.self, forKey: .statusCode)
            responseHeaders = try c.decode([CodableHeader].self, forKey: .responseHeaders).map { ($0.name, $0.value) }
            responseBody = try c.decodeIfPresent(String.self, forKey: .responseBody)
            isMock = try c.decodeIfPresent(Bool.self, forKey: .isMock) ?? false
            isTunnel = try c.decodeIfPresent(Bool.self, forKey: .isTunnel) ?? false
            isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
            isWebSocket = try c.decodeIfPresent(Bool.self, forKey: .isWebSocket) ?? false
            graphqlOperation = try c.decodeIfPresent(String.self, forKey: .graphqlOperation)
            mockSource = try c.decodeIfPresent(String.self, forKey: .mockSource)
        }

        public let id: Int
        public let timestamp: Date
        public let method: String
        public let url: String
        public let host: String
        public let appIcon: String
        public let appName: String
        public var requestHeaders: [(String, String)] = []
        public var requestBody: String?
        public var statusCode: UInt?
        public var responseHeaders: [(String, String)] = []
        public var responseBody: String?
        public var isMock: Bool = false
        public var isTunnel: Bool = false
        public var isPinned: Bool = false
        public var isWebSocket: Bool = false
        public var wsFrames: [WSFrame] = []
        public var graphqlOperation: String?
        public var mockSource: String?
        public var projectTag: String?
        /// Round-trip time from request received to response complete (nil until response arrives).
        public var duration: TimeInterval?

        public init(id: Int = 0, timestamp: Date = Date(), method: String, url: String, host: String, appIcon: String, appName: String, requestHeaders: [(String, String)] = [], requestBody: String? = nil, statusCode: UInt? = nil, responseHeaders: [(String, String)] = [], responseBody: String? = nil, isMock: Bool = false, isTunnel: Bool = false, isPinned: Bool = false) {
            self.id = id; self.timestamp = timestamp; self.method = method; self.url = url
            self.host = host; self.appIcon = appIcon; self.appName = appName
            self.requestHeaders = requestHeaders; self.requestBody = requestBody
            self.statusCode = statusCode; self.responseHeaders = responseHeaders
            self.responseBody = responseBody; self.isMock = isMock; self.isTunnel = isTunnel
            self.isPinned = isPinned
        }
    }

    private var nextId = 1

    func addRequest(method: String, url: String, host: String, appIcon: String, appName: String, headers: [(String, String)], body: String?) -> Int {
        let id = queue.sync { () -> Int in
            let currentId = nextId
            nextId += 1
            let entry = CapturedRequest(
                id: currentId,
                timestamp: Date(),
                method: method,
                url: url,
                host: host,
                appIcon: appIcon,
                appName: appName,
                requestHeaders: headers,
                requestBody: body
            )
            entries.append(entry)
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }
            return currentId
        }
        onChange?()
        return id
    }

    func addTunnel(host: String) {
        queue.sync {
            let entry = CapturedRequest(
                id: nextId,
                timestamp: Date(),
                method: "CONNECT",
                url: host,
                host: host,
                appIcon: "🔒",
                appName: "tunnel",
                isTunnel: true
            )
            nextId += 1
            entries.append(entry)
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }
        }
        onChange?()
    }

    func updateResponse(id: Int, statusCode: UInt, headers: [(String, String)], body: String?, isMock: Bool = false, mockSource: String? = nil) {
        queue.sync {
            if let idx = entries.firstIndex(where: { $0.id == id }) {
                entries[idx].statusCode = statusCode
                entries[idx].responseHeaders = headers
                entries[idx].responseBody = body
                entries[idx].isMock = isMock
                entries[idx].mockSource = mockSource
                entries[idx].duration = Date().timeIntervalSince(entries[idx].timestamp)
            }
        }
        onChange?()
    }

    public func tagProject(id: Int, project: String) {
        queue.sync {
            if let idx = entries.firstIndex(where: { $0.id == id }) {
                entries[idx].projectTag = project
            }
        }
    }

    public func getAll() -> [CapturedRequest] {
        queue.sync { entries }
    }

    public func get(id: Int) -> CapturedRequest? {
        queue.sync { entries.first(where: { $0.id == id }) }
    }

    public func count() -> Int {
        queue.sync { entries.count }
    }

    public func clear() {
        queue.sync {
            entries.removeAll()
            nextId = 1
        }
        onChange?()
    }

    func loadEntries(_ loaded: [CapturedRequest]) {
        queue.sync {
            entries = loaded
            nextId = (loaded.map { $0.id }.max() ?? 0) + 1
        }
        onChange?()
    }

    func markWebSocket(id: Int) {
        queue.sync {
            if let idx = entries.firstIndex(where: { $0.id == id }) {
                entries[idx].isWebSocket = true
            }
        }
        onChange?()
    }

    func addWSFrame(requestId: Int, frame: WSFrame) {
        queue.sync {
            if let idx = entries.firstIndex(where: { $0.id == requestId }) {
                entries[idx].wsFrames.append(frame)
            }
        }
        onChange?()
    }

    func setGraphQLOperation(id: Int, operation: String) {
        queue.sync {
            if let idx = entries.firstIndex(where: { $0.id == id }) {
                entries[idx].graphqlOperation = operation
            }
        }
        onChange?()
    }

    func markPinned(id: Int) {
        queue.sync {
            if let idx = entries.firstIndex(where: { $0.id == id }) {
                entries[idx].isPinned = true
            }
        }
        onChange?()
    }

    // MARK: - Filter & Search

    public func filter(method: String) -> [CapturedRequest] {
        queue.sync {
            entries.filter { $0.method.uppercased() == method.uppercased() }
        }
    }

    public func filter(statusRange: ClosedRange<UInt>) -> [CapturedRequest] {
        queue.sync {
            entries.filter { req in
                guard let code = req.statusCode else { return false }
                return statusRange.contains(code)
            }
        }
    }

    public func search(_ text: String) -> [CapturedRequest] {
        let lower = text.lowercased()
        return queue.sync {
            entries.filter { req in
                req.url.lowercased().contains(lower) ||
                req.host.lowercased().contains(lower) ||
                req.method.lowercased().contains(lower) ||
                (req.responseBody?.lowercased().contains(lower) ?? false) ||
                (req.requestBody?.lowercased().contains(lower) ?? false)
            }
        }
    }
}

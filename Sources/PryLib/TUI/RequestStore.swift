import Foundation

/// Codable wrapper for header tuples
public struct CodableHeader: Codable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }

    public init(from tuple: (String, String)) {
        self.name = tuple.0
        self.value = tuple.1
    }

    public var tuple: (String, String) { (name, value) }
}

/// Stores captured requests for TUI navigation
public class RequestStore {
    public static let shared = RequestStore()

    private let queue = DispatchQueue(label: "pry.requeststore")
    private var entries: [CapturedRequest] = []
    private let maxEntries = 500
    var onChange: (() -> Void)?

    public struct CapturedRequest: Codable {
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

        public init(id: Int = 0, timestamp: Date = Date(), method: String, url: String, host: String, appIcon: String, appName: String, requestHeaders: [(String, String)] = [], requestBody: String? = nil, statusCode: UInt? = nil, responseHeaders: [(String, String)] = [], responseBody: String? = nil, isMock: Bool = false, isTunnel: Bool = false, isPinned: Bool = false) {
            self.id = id; self.timestamp = timestamp; self.method = method; self.url = url
            self.host = host; self.appIcon = appIcon; self.appName = appName
            self.requestHeaders = requestHeaders; self.requestBody = requestBody
            self.statusCode = statusCode; self.responseHeaders = responseHeaders
            self.responseBody = responseBody; self.isMock = isMock; self.isTunnel = isTunnel
            self.isPinned = isPinned
        }

        // MARK: - Codable

        enum CodingKeys: String, CodingKey {
            case id, timestamp, method, url, host, appIcon, appName
            case requestHeaders, requestBody, statusCode
            case responseHeaders, responseBody
            case isMock, isTunnel, isPinned, isWebSocket
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(method, forKey: .method)
            try container.encode(url, forKey: .url)
            try container.encode(host, forKey: .host)
            try container.encode(appIcon, forKey: .appIcon)
            try container.encode(appName, forKey: .appName)
            try container.encode(requestHeaders.map { CodableHeader(from: $0) }, forKey: .requestHeaders)
            try container.encodeIfPresent(requestBody, forKey: .requestBody)
            try container.encodeIfPresent(statusCode, forKey: .statusCode)
            try container.encode(responseHeaders.map { CodableHeader(from: $0) }, forKey: .responseHeaders)
            try container.encodeIfPresent(responseBody, forKey: .responseBody)
            try container.encode(isMock, forKey: .isMock)
            try container.encode(isTunnel, forKey: .isTunnel)
            try container.encode(isPinned, forKey: .isPinned)
            try container.encode(isWebSocket, forKey: .isWebSocket)
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            timestamp = try container.decode(Date.self, forKey: .timestamp)
            method = try container.decode(String.self, forKey: .method)
            url = try container.decode(String.self, forKey: .url)
            host = try container.decode(String.self, forKey: .host)
            appIcon = try container.decode(String.self, forKey: .appIcon)
            appName = try container.decode(String.self, forKey: .appName)
            let reqHeaders = try container.decode([CodableHeader].self, forKey: .requestHeaders)
            requestHeaders = reqHeaders.map { $0.tuple }
            requestBody = try container.decodeIfPresent(String.self, forKey: .requestBody)
            statusCode = try container.decodeIfPresent(UInt.self, forKey: .statusCode)
            let respHeaders = try container.decode([CodableHeader].self, forKey: .responseHeaders)
            responseHeaders = respHeaders.map { $0.tuple }
            responseBody = try container.decodeIfPresent(String.self, forKey: .responseBody)
            isMock = try container.decode(Bool.self, forKey: .isMock)
            isTunnel = try container.decode(Bool.self, forKey: .isTunnel)
            isPinned = try container.decode(Bool.self, forKey: .isPinned)
            isWebSocket = try container.decode(Bool.self, forKey: .isWebSocket)
            wsFrames = [] // wsFrames are not persisted
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

    func updateResponse(id: Int, statusCode: UInt, headers: [(String, String)], body: String?, isMock: Bool = false) {
        queue.sync {
            if let idx = entries.firstIndex(where: { $0.id == id }) {
                entries[idx].statusCode = statusCode
                entries[idx].responseHeaders = headers
                entries[idx].responseBody = body
                entries[idx].isMock = isMock
            }
        }
        onChange?()
    }

    func getAll() -> [CapturedRequest] {
        queue.sync { entries }
    }

    func get(id: Int) -> CapturedRequest? {
        queue.sync { entries.first(where: { $0.id == id }) }
    }

    func count() -> Int {
        queue.sync { entries.count }
    }

    func clear() {
        queue.sync {
            entries.removeAll()
            nextId = 1
        }
        onChange?()
    }

    func loadEntries(_ newEntries: [CapturedRequest]) {
        queue.sync {
            entries.append(contentsOf: newEntries)
            if let maxId = newEntries.map({ $0.id }).max() {
                nextId = maxId + 1
            }
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

    func markPinned(id: Int) {
        queue.sync {
            if let idx = entries.firstIndex(where: { $0.id == id }) {
                entries[idx].isPinned = true
            }
        }
        onChange?()
    }

    // MARK: - Filter & Search

    func filter(method: String) -> [CapturedRequest] {
        queue.sync {
            entries.filter { $0.method.uppercased() == method.uppercased() }
        }
    }

    func filter(statusRange: ClosedRange<UInt>) -> [CapturedRequest] {
        queue.sync {
            entries.filter { req in
                guard let code = req.statusCode else { return false }
                return statusRange.contains(code)
            }
        }
    }

    func search(_ text: String) -> [CapturedRequest] {
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

import Foundation

/// Stores captured requests for TUI navigation
public class RequestStore {
    public static let shared = RequestStore()

    private let queue = DispatchQueue(label: "pry.requeststore")
    private var entries: [CapturedRequest] = []
    private let maxEntries = 500
    var onChange: (() -> Void)?

    public struct CapturedRequest {
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

        public init(id: Int = 0, timestamp: Date = Date(), method: String, url: String, host: String, appIcon: String, appName: String, requestHeaders: [(String, String)] = [], requestBody: String? = nil, statusCode: UInt? = nil, responseHeaders: [(String, String)] = [], responseBody: String? = nil, isMock: Bool = false, isTunnel: Bool = false) {
            self.id = id; self.timestamp = timestamp; self.method = method; self.url = url
            self.host = host; self.appIcon = appIcon; self.appName = appName
            self.requestHeaders = requestHeaders; self.requestBody = requestBody
            self.statusCode = statusCode; self.responseHeaders = responseHeaders
            self.responseBody = responseBody; self.isMock = isMock; self.isTunnel = isTunnel
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
        queue.sync { entries.removeAll() }
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

import Foundation

/// Stores captured requests for TUI navigation
class RequestStore {
    static let shared = RequestStore()

    private let queue = DispatchQueue(label: "pry.requeststore")
    private var entries: [CapturedRequest] = []
    private let maxEntries = 500
    var onChange: (() -> Void)?

    struct CapturedRequest {
        let id: Int
        let timestamp: Date
        let method: String
        let url: String
        let host: String
        let appIcon: String
        let appName: String
        var requestHeaders: [(String, String)] = []
        var requestBody: String?
        var statusCode: UInt?
        var responseHeaders: [(String, String)] = []
        var responseBody: String?
        var isMock: Bool = false
        var isTunnel: Bool = false
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
}

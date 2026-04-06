import Foundation
import Observation
import PryLib

/// @Observable bridge over ProxyServer, Watchlist, and Config for SwiftUI.
@available(macOS 14, *)
@Observable
@MainActor
public final class ProxyManager {
    public var isRunning = false
    public var port: Int
    public var requestCount: Int = 0
    public var domains: [String] = []

    private let serverBox = ServerBox()

    public init(port: Int = Config.port()) {
        self.port = port
    }

    public func start() throws {
        let s = ProxyServer(port: port)
        try s.start()
        serverBox.server = s
        isRunning = true
        reloadDomains()
    }

    public func stop() {
        serverBox.shutdownIfNeeded()
        isRunning = false
    }

    public func reloadDomains() {
        domains = Watchlist.load().sorted()
    }

    public func addDomain(_ domain: String) {
        Watchlist.add(domain)
        reloadDomains()
    }

    public func removeDomain(_ domain: String) {
        Watchlist.remove(domain)
        reloadDomains()
    }

    deinit {
        serverBox.shutdownIfNeeded()
    }
}

/// Thread-safe box to hold ProxyServer reference, enabling deinit access
/// without violating MainActor isolation.
private final class ServerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _server: ProxyServer?

    var server: ProxyServer? {
        get { lock.withLock { _server } }
        set { lock.withLock { _server = newValue } }
    }

    func shutdownIfNeeded() {
        lock.withLock {
            _server?.shutdown()
            _server = nil
        }
    }
}

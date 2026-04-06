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
        serverBox.server?.shutdown()
        serverBox.server = nil
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
        serverBox.server?.shutdown()
    }
}

/// Non-isolated box to hold ProxyServer reference, enabling deinit access.
private final class ServerBox: Sendable {
    nonisolated(unsafe) var server: ProxyServer?
}

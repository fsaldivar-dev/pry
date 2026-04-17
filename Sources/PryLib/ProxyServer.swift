import NIO
import NIOHTTP1
import Foundation

public final class ProxyServer {
    private let port: Int
    private let group: MultiThreadedEventLoopGroup
    private var channel: Channel?
    private let ca: CertificateAuthority?
    /// Registry opcional de interceptors de la arquitectura nueva (ADR-006).
    /// Si nil, el proxy funciona con sólo el flow legacy (BlockList.isBlocked, etc).
    /// Cuando PryApp arranca, pasa `core.interceptors` para que la chain nueva
    /// se ejecute antes del flow legacy.
    public let interceptors: InterceptorRegistry?

    /// Bus opcional para observers (Recordings, métricas, UI reactiva). PryApp
    /// pasa `core.bus`; CLI lo deja nil y no emite eventos.
    public let eventBus: EventBus?

    public init(port: Int = Config.defaultPort, interceptors: InterceptorRegistry? = nil, eventBus: EventBus? = nil) {
        self.port = port
        self.interceptors = interceptors
        self.eventBus = eventBus
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        // Try to init CA — if it fails, TLS interception disabled
        do {
            self.ca = try CertificateAuthority()
        } catch {
            print("⚠️  CA init failed: \(error). HTTPS interception disabled.")
            self.ca = nil
        }
    }

    public func start() throws {
        let filter = Config.get("filter")
        let watchlist = Watchlist.load()
        let mocks = Config.loadMocks()
        let ca = self.ca
        let interceptors = self.interceptors
        let eventBus = self.eventBus

        // Load legacy mocks from /tmp/pry.mocks into MockEngine
        for (path, body) in mocks {
            let mock = UnifiedMock(pattern: path, body: body, source: .loose)
            MockEngine.shared.addLooseMock(mock)
        }

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(
                        ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes))
                    )
                    try channel.pipeline.syncOperations.addHandler(HTTPResponseEncoder())
                    try channel.pipeline.syncOperations.addHandler(ConnectHandler(ca: ca, interceptors: interceptors, eventBus: eventBus))
                    try channel.pipeline.syncOperations.addHandler(HTTPInterceptor(filter: filter, interceptors: interceptors, eventBus: eventBus))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.autoRead, value: true)

        let channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
        self.channel = channel

        // Save PID
        let pid = ProcessInfo.processInfo.processIdentifier
        try? "\(pid)".write(toFile: Config.pidFile, atomically: true, encoding: .utf8)

        let out = OutputBroker.shared
        out.log("🐱 Pry listening on :\(port)", type: .info)
        if ca != nil {
            out.log("   HTTPS interception: enabled", type: .info)
        }
        if !watchlist.isEmpty {
            out.log("   Intercepting \(watchlist.count) domain(s): \(watchlist.sorted().joined(separator: ", "))", type: .info)
        }
        if !mocks.isEmpty {
            out.log("   \(mocks.count) mock(s) loaded", type: .info)
        }
    }

    /// Blocking start — for headless mode
    public func startAndWait() throws {
        try start()
        try channel?.closeFuture.wait()
    }

    public func shutdown() {
        try? channel?.close().wait()
        try? group.syncShutdownGracefully()
        try? FileManager.default.removeItem(atPath: Config.pidFile)
    }
}

import NIO
import NIOHTTP1
import Foundation

public final class ProxyServer {
    private let port: Int
    private let group: MultiThreadedEventLoopGroup
    private var channel: Channel?
    private let ca: CertificateAuthority?

    public init(port: Int = Config.defaultPort) {
        self.port = port
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

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(
                        ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes))
                    )
                    try channel.pipeline.syncOperations.addHandler(HTTPResponseEncoder())
                    if let throttle = NetworkThrottle.current {
                        try channel.pipeline.syncOperations.addHandler(ThrottleHandler(config: throttle))
                    }
                    try channel.pipeline.syncOperations.addHandler(ConnectHandler(ca: ca))
                    try channel.pipeline.syncOperations.addHandler(HTTPInterceptor(filter: filter))
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

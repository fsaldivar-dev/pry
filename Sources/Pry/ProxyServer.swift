import NIO
import NIOHTTP1
import Foundation

final class ProxyServer {
    private let port: Int
    private let group: MultiThreadedEventLoopGroup
    private var channel: Channel?
    private let ca: CertificateAuthority?

    init(port: Int = Config.defaultPort) {
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

    func start() throws {
        let mocks = Config.loadMocks()
        let filter = Config.get("filter")
        let watchlist = Watchlist.load()
        let ca = self.ca

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    // forwardBytes is CRITICAL: after CONNECT 200, leftover TLS bytes
                    // must be forwarded as raw bytes, not parsed as HTTP
                    try channel.pipeline.syncOperations.addHandler(
                        ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes))
                    )
                    try channel.pipeline.syncOperations.addHandler(HTTPResponseEncoder())
                    try channel.pipeline.syncOperations.addHandler(ConnectHandler(ca: ca))
                    try channel.pipeline.syncOperations.addHandler(HTTPInterceptor(mocks: mocks, filter: filter))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.autoRead, value: true)

        let channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
        self.channel = channel

        // Save PID
        let pid = ProcessInfo.processInfo.processIdentifier
        try? "\(pid)".write(toFile: Config.pidFile, atomically: true, encoding: .utf8)

        let mockCount = mocks.count
        print("🐱 Pry listening on :\(port)")
        if ca != nil {
            print("   HTTPS interception: enabled")
        }
        if !watchlist.isEmpty {
            print("   Intercepting \(watchlist.count) domain(s): \(watchlist.sorted().joined(separator: ", "))")
        } else {
            print("   No domains in watchlist (HTTPS passthrough)")
        }
        if mockCount > 0 {
            print("   \(mockCount) mock(s) loaded")
        }
        if let filter = filter {
            print("   Filtering: \(filter)")
        }
        print("   Press Ctrl+C to stop\n")

        // Block until channel closes
        try channel.closeFuture.wait()
    }

    func shutdown() {
        try? channel?.close().wait()
        try? group.syncShutdownGracefully()
        try? FileManager.default.removeItem(atPath: Config.pidFile)
    }
}

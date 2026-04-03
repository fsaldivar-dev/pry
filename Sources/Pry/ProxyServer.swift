import NIO
import NIOHTTP1
import Foundation

final class ProxyServer {
    private let port: Int
    private let group: MultiThreadedEventLoopGroup
    private var channel: Channel?

    init(port: Int = Config.defaultPort) {
        self.port = port
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }

    func start() throws {
        let mocks = Config.loadMocks()
        let filter = Config.get("filter")

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPInterceptor(mocks: mocks, filter: filter))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        let channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
        self.channel = channel

        // Save PID
        let pid = ProcessInfo.processInfo.processIdentifier
        try? "\(pid)".write(toFile: Config.pidFile, atomically: true, encoding: .utf8)

        let mockCount = mocks.count
        print("🐱 Pry listening on :\(port)")
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

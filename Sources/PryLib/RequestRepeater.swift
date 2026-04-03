import Foundation
import NIO
import NIOHTTP1

public struct RequestRepeater {
    /// Repeat a captured request through the proxy itself
    /// This sends the request to localhost:proxyPort which then forwards it
    public static func repeat_(request req: RequestStore.CapturedRequest, proxyPort: Int = Config.defaultPort) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let host = req.host
        let port = 80
        let isHTTPS = Watchlist.matches(host)

        // Connect through the proxy
        do {
            let channel = try ClientBootstrap(group: group)
                .channelInitializer { channel in
                    channel.pipeline.addHTTPClientHandlers()
                }
                .connect(host: "127.0.0.1", port: proxyPort)
                .wait()

            // Build the request
            let uri = isHTTPS ? req.url : "http://\(host)\(req.url)"
            var headers = NIOHTTP1.HTTPHeaders()
            headers.add(name: "Host", value: host)
            for (name, value) in req.requestHeaders {
                headers.replaceOrAdd(name: name, value: value)
            }

            let head = NIOHTTP1.HTTPRequestHead(
                version: .http1_1,
                method: NIOHTTP1.HTTPMethod(rawValue: req.method),
                uri: uri,
                headers: headers
            )

            channel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)
            if let body = req.requestBody {
                var buffer = channel.allocator.buffer(capacity: body.utf8.count)
                buffer.writeString(body)
                channel.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(buffer))), promise: nil)
            }
            channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)

            // Wait briefly for response
            Thread.sleep(forTimeInterval: 0.5)
            channel.close(promise: nil)

            OutputBroker.shared.log(info("🔄 Repeated: \(req.method) \(req.url)"), type: .info)
        } catch {
            OutputBroker.shared.log(errText("🔄 Repeat failed: \(error)"), type: .error)
        }
    }
}

import NIO
import NIOCore
import NIOHTTP1
import NIOSSL
import Foundation

/// Handles reverse proxy mode — receives requests and forwards to a fixed target origin.
public final class ReverseProxyHandler: ChannelInboundHandler, @unchecked Sendable {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart

    private let targetHost: String
    private let targetPort: Int
    private let targetIsHTTPS: Bool
    private var requestHead: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer?

    public init(targetHost: String, targetPort: Int, targetIsHTTPS: Bool) {
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.targetIsHTTPS = targetIsHTTPS
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            requestHead = head
            bodyBuffer = context.channel.allocator.buffer(capacity: 0)
        case .body(var buf):
            bodyBuffer?.writeBuffer(&buf)
        case .end:
            guard let head = requestHead else { return }
            forwardToTarget(context: context, head: head, body: bodyBuffer)
            requestHead = nil
            bodyBuffer = nil
        }
    }

    private func forwardToTarget(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
        let requestId = BodyPrinter.printRequestHead(head, host: targetHost, port: targetPort)
        BodyPrinter.printRequestBody(body)
        Config.appendLog("\(head.method) \(head.uri) -> \(targetHost):\(targetPort)")

        let clientChannel = context.channel

        if targetIsHTTPS {
            do {
                let tlsConfig = TLSConfiguration.makeClientConfiguration()
                let sslContext = try NIOSSLContext(configuration: tlsConfig)
                ClientBootstrap(group: context.eventLoop)
                    .channelInitializer { channel in
                        let sslHandler = try! NIOSSLClientHandler(context: sslContext, serverHostname: self.targetHost)
                        return channel.pipeline.addHandler(sslHandler).flatMap {
                            channel.pipeline.addHTTPClientHandlers()
                        }.flatMap {
                            channel.pipeline.addHandler(ReverseResponseForwarder(clientChannel: clientChannel, host: self.targetHost, requestId: requestId))
                        }
                    }
                    .connect(host: targetHost, port: targetPort)
                    .whenComplete { self.handleConnect($0, context: context, head: head, body: body) }
            } catch {
                OutputBroker.shared.log(errText("!!! Reverse proxy TLS error: \(error)"))
                context.close(promise: nil)
            }
        } else {
            ClientBootstrap(group: context.eventLoop)
                .channelInitializer { channel in
                    channel.pipeline.addHTTPClientHandlers().flatMap {
                        channel.pipeline.addHandler(ReverseResponseForwarder(clientChannel: clientChannel, host: self.targetHost, requestId: requestId))
                    }
                }
                .connect(host: targetHost, port: targetPort)
                .whenComplete { self.handleConnect($0, context: context, head: head, body: body) }
        }
    }

    private func handleConnect(_ result: Result<Channel, Error>, context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
        switch result {
        case .success(let remoteChannel):
            var forwardHead = head
            forwardHead.headers.replaceOrAdd(name: "Host", value: targetHost)
            remoteChannel.write(NIOAny(HTTPClientRequestPart.head(forwardHead)), promise: nil)
            if let body = body, body.readableBytes > 0 {
                remoteChannel.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(body))), promise: nil)
            }
            remoteChannel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)
        case .failure(let error):
            OutputBroker.shared.log(errText("!!! Reverse proxy forward failed: \(error)"))
            context.close(promise: nil)
        }
    }

    /// Parse a target origin URL into components
    public static func parseTargetOrigin(_ url: String) -> (host: String, port: Int, isHTTPS: Bool) {
        var s = url
        var isHTTPS = true
        if s.hasPrefix("https://") {
            s = String(s.dropFirst(8))
            isHTTPS = true
        } else if s.hasPrefix("http://") {
            s = String(s.dropFirst(7))
            isHTTPS = false
        }
        // Remove trailing path
        if let slashIdx = s.firstIndex(of: "/") { s = String(s[s.startIndex..<slashIdx]) }

        let parts = s.split(separator: ":", maxSplits: 1)
        let host = String(parts[0])
        let port = parts.count > 1 ? Int(parts[1]) ?? (isHTTPS ? 443 : 80) : (isHTTPS ? 443 : 80)
        return (host, port, isHTTPS)
    }
}

/// Forwards responses from target back to the client in reverse proxy mode
final class ReverseResponseForwarder: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart

    private let clientChannel: Channel
    private let host: String
    private let requestId: Int
    private var statusCode: UInt = 0
    private var contentType: String?
    private var responseBody: ByteBuffer?

    init(clientChannel: Channel, host: String, requestId: Int) {
        self.clientChannel = clientChannel
        self.host = host
        self.requestId = requestId
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            statusCode = head.status.code
            BodyPrinter.printResponseHead(head, host: host)
            contentType = head.headers["Content-Type"].first
            responseBody = context.channel.allocator.buffer(capacity: 0)
            let serverHead = HTTPResponseHead(version: head.version, status: head.status, headers: head.headers)
            clientChannel.write(NIOAny(HTTPServerResponsePart.head(serverHead)), promise: nil)
        case .body(var buffer):
            responseBody?.writeBuffer(&buffer)
            clientChannel.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
        case .end(let trailers):
            if let body = responseBody {
                BodyPrinter.printResponseBody(body, contentType: contentType)
                var buf = body
                let bodyStr = buf.readString(length: buf.readableBytes)
                BodyPrinter.storeResponse(requestId: requestId, statusCode: statusCode, headers: [], body: bodyStr)
            }
            clientChannel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(trailers))).whenComplete { _ in
                self.clientChannel.close(promise: nil)
            }
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        OutputBroker.shared.log(errText("!!! Reverse proxy response error: \(error)"))
        clientChannel.close(promise: nil)
        context.close(promise: nil)
    }
}

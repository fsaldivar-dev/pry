import NIO
import NIOCore
import NIOHTTP1
import NIOSSL
import Foundation

final class ConnectHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private enum State {
        case idle
        case beganConnecting
        case awaitingEnd(connectResult: Channel)
        case awaitingConnection(pendingBytes: [NIOAny])
        case upgradeComplete(pendingBytes: [NIOAny])
        case upgradeFailed
    }

    private var state: State = .idle
    private let ca: CertificateAuthority?
    // Stored as instance properties so all states can access them
    private var connectHost: String = ""
    private var connectPort: Int = 443
    private var shouldIntercept: Bool = false

    init(ca: CertificateAuthority?) {
        self.ca = ca
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch state {
        case .idle:
            handleInitialMessage(context: context, data: unwrapInboundIn(data), rawData: data)

        case .beganConnecting:
            // .end arrives before TCP connect completes — common on fast networks
            if case .end = unwrapInboundIn(data) {
                state = .awaitingConnection(pendingBytes: [])
                removeDecoder(context: context)
            }

        case .awaitingEnd(let peerChannel):
            if case .end = unwrapInboundIn(data) {
                state = .upgradeComplete(pendingBytes: [])
                removeDecoder(context: context)
                performUpgrade(peerChannel: peerChannel, context: context)
            }

        case .awaitingConnection(var pendingBytes):
            state = .awaitingConnection(pendingBytes: [])
            pendingBytes.append(data)
            state = .awaitingConnection(pendingBytes: pendingBytes)

        case .upgradeComplete(var pendingBytes):
            state = .upgradeComplete(pendingBytes: [])
            pendingBytes.append(data)
            state = .upgradeComplete(pendingBytes: pendingBytes)

        case .upgradeFailed:
            break
        }
    }

    func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken) {
        var didRead = false
        while case .upgradeComplete(var pendingBytes) = state, pendingBytes.count > 0 {
            state = .upgradeComplete(pendingBytes: [])
            let next = pendingBytes.removeFirst()
            state = .upgradeComplete(pendingBytes: pendingBytes)
            context.fireChannelRead(next)
            didRead = true
        }
        if didRead {
            context.fireChannelReadComplete()
        }
        context.leavePipeline(removalToken: removalToken)
    }

    private func handleInitialMessage(context: ChannelHandlerContext, data: InboundIn, rawData: NIOAny) {
        guard case .head(let head) = data else {
            context.fireChannelRead(rawData)
            return
        }

        guard head.method == .CONNECT else {
            // Not CONNECT — forward to HTTPInterceptor
            context.fireChannelRead(rawData)
            return
        }

        let (host, port) = parseHostPort(head.uri)
        connectHost = host
        connectPort = port
        shouldIntercept = ca != nil && Watchlist.matches(host)

        state = .beganConnecting
        connectTo(context: context)
    }

    private func connectTo(context: ChannelHandlerContext) {
        ClientBootstrap(group: context.eventLoop)
            .connect(host: connectHost, port: connectPort)
            .whenComplete { result in
                switch result {
                case .success(let channel):
                    self.connectSucceeded(channel: channel, context: context)
                case .failure(let error):
                    self.connectFailed(error: error, context: context)
                }
            }
    }

    private func connectSucceeded(channel: Channel, context: ChannelHandlerContext) {
        switch state {
        case .beganConnecting:
            state = .awaitingEnd(connectResult: channel)

        case .awaitingConnection(let pendingBytes):
            state = .upgradeComplete(pendingBytes: pendingBytes)
            performUpgrade(peerChannel: channel, context: context)

        default:
            channel.close(mode: .all, promise: nil)
            context.close(promise: nil)
        }
    }

    private func connectFailed(error: Error, context: ChannelHandlerContext) {
        print("!!! CONNECT failed: \(error)")
        state = .upgradeFailed
        let headers = HTTPHeaders([("Content-Length", "0"), ("Connection", "close")])
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .badGateway, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(mode: .output, promise: nil)
        }
    }

    private func performUpgrade(peerChannel: Channel, context: ChannelHandlerContext) {
        // Send 200 Connection Established
        let headers = HTTPHeaders([("Content-Length", "0")])
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)

        // Remove HTTP encoder
        removeEncoder(context: context)

        if shouldIntercept {
            setupInterception(peerChannel: peerChannel, context: context)
        } else {
            setupTunnel(peerChannel: peerChannel, context: context)
        }
    }

    private func setupTunnel(peerChannel: Channel, context: ChannelHandlerContext) {
        print("--- TUNNEL \(connectHost) (passthrough)")
        Config.appendLog("TUNNEL \(connectHost)")

        let (localGlue, peerGlue) = GlueHandler.matchedPair()
        do {
            // Remove HTTPInterceptor — MUST succeed or TLS bytes get parsed as HTTP
            if let interceptor = try? context.pipeline.syncOperations.handler(type: HTTPInterceptor.self) {
                context.pipeline.syncOperations.removeHandler(interceptor, promise: nil)
            }
            try context.pipeline.syncOperations.addHandler(localGlue)
            try peerChannel.pipeline.syncOperations.addHandler(peerGlue)
            // Remove self last — this forwards any pending bytes via removeHandler()
            context.pipeline.syncOperations.removeHandler(self, promise: nil)
        } catch {
            print("!!! Tunnel setup failed for \(connectHost): \(error)")
            peerChannel.close(mode: .all, promise: nil)
            context.close(promise: nil)
        }
    }

    private func setupInterception(peerChannel: Channel, context: ChannelHandlerContext) {
        let host = connectHost
        let port = connectPort
        guard let ca = ca else {
            setupTunnel(peerChannel: peerChannel, context: context)
            return
        }

        print(">>> INTERCEPT \(host)")
        Config.appendLog("INTERCEPT \(host)")

        // Close raw remote channel — we'll make a TLS one later
        peerChannel.close(promise: nil)

        do {
            let (cert, key) = try ca.generateCert(for: host)
            let tlsConfig = TLSConfiguration.makeServerConfiguration(
                certificateChain: [.certificate(cert)],
                privateKey: .privateKey(key)
            )
            let sslContext = try NIOSSLContext(configuration: tlsConfig)
            let sslHandler = NIOSSLServerHandler(context: sslContext)

            // Remove HTTPInterceptor
            if let interceptor = try? context.pipeline.syncOperations.handler(type: HTTPInterceptor.self) {
                try context.pipeline.syncOperations.removeHandler(interceptor)
            }

            // Add TLS handler, then re-add HTTP handlers for decrypted traffic
            context.pipeline.addHandler(sslHandler, position: .first).flatMap {
                context.pipeline.configureHTTPServerPipeline()
            }.flatMap {
                context.pipeline.addHandler(TLSForwarder(host: host, port: port, eventLoop: context.eventLoop))
            }.flatMap {
                context.pipeline.removeHandler(self)
            }.whenFailure { error in
                print("!!! TLS setup failed for \(host): \(error)")
                context.close(promise: nil)
            }
        } catch {
            print("!!! Cert generation failed for \(host): \(error)")
            context.close(promise: nil)
        }
    }

    private func removeDecoder(context: ChannelHandlerContext) {
        if let ctx = try? context.pipeline.syncOperations.context(
            handlerType: ByteToMessageHandler<HTTPRequestDecoder>.self
        ) {
            context.pipeline.syncOperations.removeHandler(context: ctx, promise: nil)
        }
    }

    private func removeEncoder(context: ChannelHandlerContext) {
        if let ctx = try? context.pipeline.syncOperations.context(
            handlerType: HTTPResponseEncoder.self
        ) {
            context.pipeline.syncOperations.removeHandler(context: ctx, promise: nil)
        }
    }

    private func parseHostPort(_ hostPort: String) -> (String, Int) {
        let parts = hostPort.split(separator: ":", maxSplits: 1)
        let host = String(parts[0])
        let port = parts.count > 1 ? Int(parts[1]) ?? 443 : 443
        return (host, port)
    }
}

// Handles decrypted HTTP from TLS-intercepted connections
final class TLSForwarder: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let host: String
    private let port: Int
    private let eventLoop: EventLoop
    private var requestHead: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer?

    init(host: String, port: Int, eventLoop: EventLoop) {
        self.host = host
        self.port = port
        self.eventLoop = eventLoop
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            requestHead = head
            bodyBuffer = context.channel.allocator.buffer(capacity: 0)
        case .body(var buf):
            bodyBuffer?.writeBuffer(&buf)
        case .end:
            guard let head = requestHead else { return }
            handleDecryptedRequest(context: context, head: head, body: bodyBuffer)
            requestHead = nil
            bodyBuffer = nil
        }
    }

    private func handleDecryptedRequest(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
        let logEntry = "\(head.method) https://\(host)\(head.uri)"
        print(">>> \(logEntry)")
        Config.appendLog(logEntry)

        // Check mocks — supports both "domain:path" and simple "/path" formats
        let mocks = Config.loadMocks()
        for (mockKey, response) in mocks {
            let matches: Bool
            if mockKey.contains(":") {
                let parts = mockKey.split(separator: ":", maxSplits: 1)
                let mockDomain = String(parts[0])
                let mockPath = String(parts[1])
                matches = host.contains(mockDomain) && head.uri.hasPrefix(mockPath)
            } else {
                matches = head.uri.hasPrefix(mockKey)
            }
            if matches {
                print("<<< MOCK \(head.uri) (200 OK)")
                Config.appendLog("MOCK \(head.uri) -> 200 OK")
                var headers = HTTPHeaders()
                headers.add(name: "Content-Type", value: "application/json")
                headers.add(name: "X-Pry-Mock", value: "true")
                let responseHead = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
                context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
                var buffer = context.channel.allocator.buffer(capacity: response.utf8.count)
                buffer.writeString(response)
                context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
                return
            }
        }

        // Forward to real server via TLS
        do {
            let tlsConfig = TLSConfiguration.makeClientConfiguration()
            let sslContext = try NIOSSLContext(configuration: tlsConfig)

            ClientBootstrap(group: eventLoop)
                .channelInitializer { channel in
                    let sslHandler = try! NIOSSLClientHandler(context: sslContext, serverHostname: self.host)
                    return channel.pipeline.addHandler(sslHandler).flatMap {
                        channel.pipeline.addHTTPClientHandlers()
                    }.flatMap {
                        channel.pipeline.addHandler(TLSResponseForwarder(clientChannel: context.channel, host: self.host))
                    }
                }
                .connect(host: host, port: port)
                .whenComplete { result in
                    switch result {
                    case .success(let remoteChannel):
                        var forwardHead = head
                        forwardHead.headers.replaceOrAdd(name: "Host", value: self.host)
                        remoteChannel.write(NIOAny(HTTPClientRequestPart.head(forwardHead)), promise: nil)
                        if let body = body, body.readableBytes > 0 {
                            remoteChannel.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(body))), promise: nil)
                        }
                        remoteChannel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)
                    case .failure(let error):
                        print("!!! TLS forward failed to \(self.host): \(error)")
                        context.close(promise: nil)
                    }
                }
        } catch {
            print("!!! TLS context failed: \(error)")
            context.close(promise: nil)
        }
    }
}

final class TLSResponseForwarder: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart

    private let clientChannel: Channel
    private let host: String

    init(clientChannel: Channel, host: String) {
        self.clientChannel = clientChannel
        self.host = host
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            print("<<< \(head.status.code) https://\(host)")
            Config.appendLog("RESPONSE https://\(host) -> \(head.status.code)")
            let serverHead = HTTPResponseHead(version: head.version, status: head.status, headers: head.headers)
            clientChannel.write(NIOAny(HTTPServerResponsePart.head(serverHead)), promise: nil)
        case .body(let buffer):
            clientChannel.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
        case .end(let trailers):
            clientChannel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(trailers))).whenComplete { _ in
                self.clientChannel.close(promise: nil)
            }
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("!!! TLS response error from \(host): \(error)")
        clientChannel.close(promise: nil)
        context.close(promise: nil)
    }
}

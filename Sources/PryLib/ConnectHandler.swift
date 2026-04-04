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

        // Block list check
        if BlockList.isBlocked(host) {
            OutputBroker.shared.log(errText("🚫 BLOCKED \(host)"), type: .error)
            let headers = HTTPHeaders([("Content-Length", "0"), ("Connection", "close")])
            let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .forbidden, headers: headers)
            context.write(wrapOutboundOut(.head(head)), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
                context.close(mode: .output, promise: nil)
            }
            return
        }

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
        OutputBroker.shared.log(errText("!!! CONNECT failed: \(error)"))
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
        OutputBroker.shared.log(tunnel("--- TUNNEL \(connectHost) (passthrough)"), type: .tunnel)
        BodyPrinter.storeTunnel(host: connectHost)
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
            OutputBroker.shared.log(errText("!!! Tunnel setup failed for \(connectHost): \(error)"))
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

        print(info(">>> INTERCEPT \(host)"))
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

            // Add TLS handler, pinning detector, then re-add HTTP handlers for decrypted traffic
            let pinningDetector = CertificatePinningDetector(host: host)
            context.pipeline.addHandler(sslHandler, position: .first).flatMap {
                context.pipeline.addHandler(pinningDetector, position: .after(sslHandler))
            }.flatMap {
                context.pipeline.configureHTTPServerPipeline()
            }.flatMap {
                context.pipeline.addHandler(TLSForwarder(host: host, port: port, eventLoop: context.eventLoop))
            }.flatMap {
                context.pipeline.removeHandler(self)
            }.whenFailure { error in
                OutputBroker.shared.log(errText("!!! TLS setup failed for \(host): \(error)"))
                context.close(promise: nil)
            }
        } catch {
            OutputBroker.shared.log(errText("!!! Cert generation failed for \(host): \(error)"))
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
    private var lastRequestId: Int = 0

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
        let requestId = BodyPrinter.printRequestHead(head, host: host, port: port)
        BodyPrinter.printRequestBody(body)
        Config.appendLog(logEntry)

        // WebSocket upgrade detection
        let upgradeHeader = head.headers["Upgrade"].first?.lowercased()
        if upgradeHeader == "websocket" {
            OutputBroker.shared.log(info("🔌 WebSocket upgrade detected: wss://\(host)\(head.uri)"), type: .info)
            Config.appendLog("WEBSOCKET wss://\(host)\(head.uri)")
            RequestStore.shared.markWebSocket(id: requestId)
            forwardWebSocketUpgrade(context: context, head: head, body: body, requestId: requestId)
            return
        }

        // Breakpoint check
        if BreakpointStore.shared.shouldBreak(url: head.uri, host: host) {
            RequestStore.shared.updateResponse(id: requestId, statusCode: 0, headers: [], body: "⏸️ Paused at breakpoint")
            let future = RequestBreakpointManager.shared.pause(id: requestId, head: head, body: body, host: host, eventLoop: eventLoop)
            future.whenSuccess { [self] action in
                switch action {
                case .resume:
                    self.continueRequest(context: context, head: head, body: body, requestId: requestId)
                case .modify(let newHeaders, let newBody):
                    var modifiedHead = head
                    if let headers = newHeaders {
                        for (name, value) in headers {
                            modifiedHead.headers.replaceOrAdd(name: name, value: value)
                        }
                    }
                    var modifiedBody = body
                    if let bodyStr = newBody {
                        var buf = context.channel.allocator.buffer(capacity: bodyStr.utf8.count)
                        buf.writeString(bodyStr)
                        modifiedBody = buf
                    }
                    self.continueRequest(context: context, head: modifiedHead, body: modifiedBody, requestId: requestId)
                case .cancel:
                    context.close(promise: nil)
                }
            }
            return
        }

        continueRequest(context: context, head: head, body: body, requestId: requestId)
    }

    private func continueRequest(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?, requestId: Int) {
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
                BodyPrinter.printMock(path: head.uri, json: response)
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

        // Rule Engine: apply scripting rules
        let matchingRules = RuleEngine.matchingRules(for: head.uri, method: "\(head.method)")
        if !matchingRules.isEmpty {
            var ruleHeaders = head.headers.map { ($0.name, $0.value) }
            let ruleResult = RuleEngine.applyRequestRules(rules: matchingRules, headers: &ruleHeaders)
            if ruleResult.shouldDrop {
                context.close(promise: nil)
                return
            }
        }

        // No-cache: strip caching headers
        var forwardingHead = head
        if Config.get("nocache") == "true" {
            forwardingHead.headers.replaceOrAdd(name: "Cache-Control", value: "no-store, no-cache")
            forwardingHead.headers.replaceOrAdd(name: "Pragma", value: "no-cache")
            forwardingHead.headers.remove(name: "If-None-Match")
            forwardingHead.headers.remove(name: "If-Modified-Since")
        }

        // Map Remote + DNS Spoofing
        var connectHost = self.host
        if let remapped = MapRemote.match(host: self.host) {
            connectHost = remapped
            OutputBroker.shared.log(info(">>> REDIRECT \(self.host) → \(remapped)"), type: .info)
        }
        if let spoofedIP = DNSSpoofing.resolve(connectHost) {
            connectHost = spoofedIP
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
                .connect(host: connectHost, port: port)
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
                        OutputBroker.shared.log(errText("!!! TLS forward failed to \(self.host): \(error)"))
                        context.close(promise: nil)
                    }
                }
        } catch {
            OutputBroker.shared.log(errText("!!! TLS context failed: \(error)"))
            context.close(promise: nil)
        }
    }

    private func forwardWebSocketUpgrade(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?, requestId: Int) {
        do {
            let tlsConfig = TLSConfiguration.makeClientConfiguration()
            let sslContext = try NIOSSLContext(configuration: tlsConfig)
            let clientChannel = context.channel

            ClientBootstrap(group: eventLoop)
                .channelInitializer { channel in
                    let sslHandler = try! NIOSSLClientHandler(context: sslContext, serverHostname: self.host)
                    return channel.pipeline.addHandler(sslHandler).flatMap {
                        channel.pipeline.addHTTPClientHandlers()
                    }.flatMap {
                        channel.pipeline.addHandler(
                            WebSocketUpgradeForwarder(
                                clientChannel: clientChannel,
                                host: self.host,
                                requestId: requestId
                            )
                        )
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
                        OutputBroker.shared.log(errText("!!! WebSocket upgrade forward failed to \(self.host): \(error)"))
                        context.close(promise: nil)
                    }
                }
        } catch {
            OutputBroker.shared.log(errText("!!! WebSocket TLS context failed: \(error)"))
            context.close(promise: nil)
        }
    }
}

/// Handles WebSocket upgrade response from server.
/// On 101, strips HTTP handlers and sets up WebSocket frame interception with GlueHandler.
final class WebSocketUpgradeForwarder: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart

    private let clientChannel: Channel
    private let host: String
    private let requestId: Int

    init(clientChannel: Channel, host: String, requestId: Int) {
        self.clientChannel = clientChannel
        self.host = host
        self.requestId = requestId
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            // Forward the upgrade response to client
            let serverHead = NIOHTTP1.HTTPResponseHead(version: head.version, status: head.status, headers: head.headers)
            clientChannel.write(NIOAny(HTTPServerResponsePart.head(serverHead)), promise: nil)

            if head.status == .switchingProtocols {
                OutputBroker.shared.log(info("🔌 WebSocket connection established: wss://\(host)"), type: .info)
                RequestStore.shared.updateResponse(
                    id: requestId,
                    statusCode: UInt(head.status.code),
                    headers: head.headers.map { ($0.name, $0.value) },
                    body: "WebSocket connection active"
                )
            }

        case .body(var buffer):
            clientChannel.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)

        case .end:
            clientChannel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)

            // After 101 response completes, switch to raw WebSocket mode
            // Remove HTTP handlers and set up bidirectional frame interception
            let remoteChannel = context.channel
            let wsInterceptor = WebSocketInterceptor(host: host, requestId: requestId)

            // Set up glue + interceptor on both sides
            let (localGlue, remoteGlue) = GlueHandler.matchedPair()

            // Remove HTTP handlers from client pipeline and add WS interceptor + glue
            _ = clientChannel.pipeline.removeHandler(name: "HTTPResponseEncoder")
            clientChannel.pipeline.addHandler(wsInterceptor).flatMap {
                self.clientChannel.pipeline.addHandler(localGlue)
            }.whenComplete { _ in
                // Remove HTTP handlers from remote pipeline and add glue
                _ = remoteChannel.pipeline.removeHandler(name: "HTTPRequestEncoder")
                remoteChannel.pipeline.addHandler(remoteGlue).whenFailure { error in
                    OutputBroker.shared.log(errText("!!! WebSocket glue setup failed: \(error)"))
                }
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        OutputBroker.shared.log(errText("!!! WebSocket upgrade error from \(host): \(error)"))
        clientChannel.close(promise: nil)
        context.close(promise: nil)
    }
}

final class TLSResponseForwarder: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart

    private let clientChannel: Channel
    private let host: String
    private var contentType: String?
    private var responseBody: ByteBuffer?

    init(clientChannel: Channel, host: String) {
        self.clientChannel = clientChannel
        self.host = host
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            BodyPrinter.printResponseHead(head, host: host, https: true)
            Config.appendLog("RESPONSE https://\(host) -> \(head.status.code)")
            contentType = head.headers["Content-Type"].first
            responseBody = context.channel.allocator.buffer(capacity: 0)
            let serverHead = NIOHTTP1.HTTPResponseHead(version: head.version, status: head.status, headers: head.headers)
            clientChannel.write(NIOAny(HTTPServerResponsePart.head(serverHead)), promise: nil)
        case .body(var buffer):
            responseBody?.writeBuffer(&buffer)
            clientChannel.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
        case .end(let trailers):
            if let body = responseBody {
                BodyPrinter.printResponseBody(body, contentType: contentType)
            }
            clientChannel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(trailers))).whenComplete { _ in
                self.clientChannel.close(promise: nil)
            }
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        OutputBroker.shared.log(errText("!!! TLS response error from \(host): \(error)"))
        clientChannel.close(promise: nil)
        context.close(promise: nil)
    }
}

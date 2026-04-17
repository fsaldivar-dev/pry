import NIO
import NIOHTTP1
import Foundation

final class HTTPInterceptor: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var requestHead: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer?
    private let filter: String?

    init(filter: String? = nil) {
        self.filter = filter
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
            handleRequest(context: context, head: head, body: bodyBuffer)
            requestHead = nil
            bodyBuffer = nil
        }
    }

    private func handleRequest(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
        let (host, port, path) = extractTarget(from: head)

        // Block list check
        if BlockList.isBlocked(host) {
            OutputBroker.shared.log(errText("🚫 BLOCKED \(host)"), type: .error)
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "application/json")
            headers.add(name: "Connection", value: "close")
            let responseHead = HTTPResponseHead(version: .http1_1, status: .forbidden, headers: headers)
            context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
            var buffer = context.channel.allocator.buffer(capacity: 0)
            buffer.writeString("{\"error\":\"blocked by Pry\"}")
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            return
        }

        // Filter check
        if let filter = filter, !host.contains(filter) {
            forwardRequest(context: context, host: host, port: port, head: head, body: body)
            return
        }

        // Log + store
        let logEntry = "\(head.method) \(head.uri) -> \(host):\(port)"
        let requestId = BodyPrinter.printRequestHead(head, host: host, port: port)
        BodyPrinter.printRequestBody(body, requestId: requestId)
        Config.appendLog(logEntry)

        // Recorder hook — capture request when recording is active
        if Recorder.shared.isRecording {
            var bodyString: String?
            if var buf = body, buf.readableBytes > 0 {
                bodyString = buf.readString(length: buf.readableBytes)
            }
            Recorder.shared.noteRequestStart(
                requestId: requestId,
                method: "\(head.method)",
                url: path,
                host: host,
                headers: head.headers.map { ($0.name, $0.value) },
                body: bodyString
            )
        }

        // Project tracking — auto-tag request with project
        let userAgent = head.headers.first(name: "User-Agent")
        if let projectName = ProjectManager.findProject(host: host, userAgent: userAgent) {
            RequestStore.shared.tagProject(id: requestId, project: projectName)
            if let ua = userAgent {
                ProjectManager.autoLearnUserAgent(project: projectName, userAgent: ua)
            }
        }

        // Breakpoint check
        if BreakpointStore.shared.shouldBreak(url: head.uri, host: host) {
            RequestStore.shared.updateResponse(id: requestId, statusCode: 0, headers: [], body: "⏸️ Paused at breakpoint")
            let future = RequestBreakpointManager.shared.pause(id: requestId, head: head, body: body, host: host, eventLoop: context.eventLoop)
            future.whenSuccess { [self] action in
                switch action {
                case .resume:
                    self.continueAfterBreakpoint(context: context, host: host, port: port, path: path, head: head, body: body, requestId: requestId)
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
                    self.continueAfterBreakpoint(context: context, host: host, port: port, path: path, head: modifiedHead, body: modifiedBody, requestId: requestId)
                case .cancel:
                    context.close(promise: nil)
                }
            }
            return
        }

        // Mock check (unified: covers status overrides + mocks)
        if let mock = MockEngine.shared.findMock(path: path, host: host, method: "\(head.method)") {
            respondWithUnifiedMock(context: context, mock: mock, path: path, host: host, requestId: requestId)
            return
        }

        // Legacy mock fallback — for mocks added via CLI while proxy is running
        let legacyMocks = Config.loadMocks()
        for (mockKey, response) in legacyMocks {
            let matches: Bool
            if mockKey.contains(":") {
                let parts = mockKey.split(separator: ":", maxSplits: 1)
                matches = host.contains(String(parts[0])) && path.hasPrefix(String(parts[1]))
            } else {
                matches = path.hasPrefix(mockKey)
            }
            if matches {
                let legacyMock = UnifiedMock(pattern: mockKey, body: response, source: .loose)
                respondWithUnifiedMock(context: context, mock: legacyMock, path: path, host: host, requestId: requestId)
                return
            }
        }

        // Map Local check (regex → local file)
        if let fileContent = MapLocal.matchContent(url: path) {
            let mapMock = UnifiedMock(pattern: path, body: fileContent, source: .loose)
            respondWithUnifiedMock(context: context, mock: mapMock, path: path, host: host, requestId: requestId)
            return
        }

        // Apply header rewrites before forwarding
        var rewrittenHead = head
        let rewrittenHeaders = HeaderRewrite.apply(to: head.headers.map { ($0.name, $0.value) })
        rewrittenHead.headers = .init(rewrittenHeaders.map { (name: $0.0, value: $0.1) })

        // Rule Engine: apply scripting rules
        let matchingRules = RuleEngine.matchingRules(for: head.uri, method: "\(head.method)")
        if !matchingRules.isEmpty {
            var ruleHeaders = rewrittenHead.headers.map { ($0.name, $0.value) }
            let ruleResult = RuleEngine.applyRequestRules(rules: matchingRules, headers: &ruleHeaders)
            rewrittenHead.headers = .init(ruleHeaders.map { (name: $0.0, value: $0.1) })
            if ruleResult.shouldDrop {
                context.close(promise: nil)
                return
            }
        }

        // No-cache: strip caching headers and add no-store
        if Config.get("nocache") == "true" {
            rewrittenHead.headers.replaceOrAdd(name: "Cache-Control", value: "no-store, no-cache")
            rewrittenHead.headers.replaceOrAdd(name: "Pragma", value: "no-cache")
            rewrittenHead.headers.remove(name: "If-None-Match")
            rewrittenHead.headers.remove(name: "If-Modified-Since")
        }

        // Map Remote: redirect to different host
        var connectHost = host
        if let remapped = MapRemote.match(host: host) {
            connectHost = remapped
            OutputBroker.shared.log(info(">>> REDIRECT \(host) → \(remapped)"), type: .info)
        }

        // DNS Spoofing: override IP resolution
        if let spoofedIP = DNSSpoofing.resolve(connectHost) {
            connectHost = spoofedIP
        }

        // Forward to real server
        forwardRequest(context: context, host: host, port: port, head: rewrittenHead, body: body, requestId: requestId, connectHost: connectHost)
    }

    private func continueAfterBreakpoint(context: ChannelHandlerContext, host: String, port: Int, path: String, head: HTTPRequestHead, body: ByteBuffer?, requestId: Int) {
        if let mock = MockEngine.shared.findMock(path: path, host: host, method: "\(head.method)") {
            respondWithUnifiedMock(context: context, mock: mock, path: path, host: host, requestId: requestId)
            return
        }
        forwardRequest(context: context, host: host, port: port, head: head, body: body, requestId: requestId)
    }

    private func respondWithUnifiedMock(context: ChannelHandlerContext, mock: UnifiedMock, path: String, host: String, requestId: Int) {
        let sourceLabel = mock.source?.label ?? "loose"
        let ct = mock.contentType ?? "application/json"

        BodyPrinter.printMock(path: path, json: mock.body)
        BodyPrinter.storeResponse(requestId: requestId, statusCode: mock.status,
                                  headers: [(ct == "application/json" ? "Content-Type" : ct, ct), ("X-Pry-Mock", "true")],
                                  body: mock.body, isMock: true, mockSource: sourceLabel)
        Config.appendLog("MOCK \(path) -> \(mock.status) [\(sourceLabel)]")
        OutputBroker.shared.log("🎭 Mock \(mock.status) → \(host)\(path) [\(sourceLabel)]", type: .mock)

        let sendResponse = { [weak self] in
            guard let self else { return }
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: ct)
            headers.add(name: "X-Pry-Mock", value: "true")
            // Add custom headers from mock
            if let customHeaders = mock.headers {
                for (name, value) in customHeaders {
                    headers.add(name: name, value: value)
                }
            }

            let responseHead = HTTPResponseHead(version: .http1_1,
                                                status: HTTPResponseStatus(statusCode: Int(mock.status)),
                                                headers: headers)
            context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)

            var buffer = context.channel.allocator.buffer(capacity: mock.body.utf8.count)
            buffer.writeString(mock.body)
            context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)

            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        }

        // Delay support
        if let delay = mock.delay, delay > 0 {
            context.eventLoop.scheduleTask(in: .milliseconds(Int64(delay))) {
                sendResponse()
            }
        } else {
            sendResponse()
        }
    }

    private func forwardRequest(context: ChannelHandlerContext, host: String, port: Int, head: HTTPRequestHead, body: ByteBuffer?, requestId: Int = 0, connectHost: String? = nil) {
        let clientChannel = context.channel
        let group = context.eventLoop
        let targetHost = connectHost ?? host

        ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(ResponseForwarder(clientChannel: clientChannel, host: host, requestId: requestId))
                }
            }
            .connect(host: targetHost, port: port)
            .whenComplete { result in
                switch result {
                case .success(let remoteChannel):
                    // Rewrite request for non-proxy form
                    var forwardHead = head
                    forwardHead.uri = head.uri.hasPrefix("http")
                        ? (URLComponents(string: head.uri)?.path ?? head.uri)
                        : head.uri
                    forwardHead.headers.replaceOrAdd(name: "Host", value: host)

                    remoteChannel.write(NIOAny(HTTPClientRequestPart.head(forwardHead)), promise: nil)
                    if let body = body, body.readableBytes > 0 {
                        remoteChannel.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(body))), promise: nil)
                    }
                    remoteChannel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)

                case .failure(let error):
                    OutputBroker.shared.log(errText("!!! Connection failed to \(host):\(port) - \(error)"))
                    Config.appendLog("ERROR \(host):\(port) - \(error)")
                    clientChannel.close(promise: nil)
                }
            }
    }

    private func extractTarget(from head: HTTPRequestHead) -> (host: String, port: Int, path: String) {
        // Absolute URI: GET http://example.com:8080/path
        if let components = URLComponents(string: head.uri),
           let urlHost = components.host {
            let port = components.port ?? 80
            let path = components.path.isEmpty ? "/" : components.path
            return (urlHost, port, path)
        }

        // Host header fallback
        let hostHeader = head.headers["Host"].first ?? "localhost"
        let parts = hostHeader.split(separator: ":")
        let host = String(parts[0])
        let port = parts.count > 1 ? Int(parts[1]) ?? 80 : 80

        return (host, port, head.uri)
    }
}

final class ResponseForwarder: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPServerResponsePart

    private let clientChannel: Channel
    private let host: String
    private let requestId: Int
    private var contentType: String?
    private var responseHead: NIOHTTP1.HTTPResponseHead?
    private var responseBody: ByteBuffer?
    private var statusCode: UInt = 0
    private var responseSent = false

    init(clientChannel: Channel, host: String, requestId: Int = 0) {
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
            Config.appendLog("RESPONSE \(host) -> \(head.status.code)")
            contentType = head.headers["Content-Type"].first
            responseHead = NIOHTTP1.HTTPResponseHead(version: head.version, status: head.status, headers: head.headers)
            responseBody = context.channel.allocator.buffer(capacity: 0)

        case .body(var buffer):
            responseBody?.writeBuffer(&buffer)

        case .end:
            sendBufferedResponse(context: context)
        }
    }

    private func sendBufferedResponse(context: ChannelHandlerContext) {
        guard !responseSent, let head = responseHead else { return }
        responseSent = true

        if let body = responseBody {
            // Decompress for display/storage if Content-Encoding indicates compression.
            // Original compressed bytes are still forwarded to the client below, unchanged.
            let contentEncoding = head.headers["Content-Encoding"].first
            var displayBuf = body
            if let enc = contentEncoding {
                var raw = body
                if let bytes = raw.readBytes(length: raw.readableBytes),
                   let inflated = BodyDecompressor.decompress(Data(bytes), encoding: enc) {
                    displayBuf = context.channel.allocator.buffer(capacity: inflated.count)
                    displayBuf.writeBytes(inflated)
                }
            }
            BodyPrinter.printResponseBody(displayBuf, contentType: contentType)
            var buf = displayBuf
            let bodyStr = buf.readString(length: buf.readableBytes)
            BodyPrinter.storeResponse(requestId: requestId, statusCode: statusCode, headers: [], body: bodyStr)

            // Recorder hook — capture response when recording is active
            if Recorder.shared.isRecording {
                Recorder.shared.noteResponseComplete(
                    requestId: requestId,
                    statusCode: statusCode,
                    headers: head.headers.map { ($0.name, $0.value) },
                    body: bodyStr
                )
            }
        }

        clientChannel.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)
        if let body = responseBody, body.readableBytes > 0 {
            clientChannel.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(body))), promise: nil)
        }
        clientChannel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil))).whenComplete { _ in
            self.clientChannel.close(promise: nil)
        }
        context.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        sendBufferedResponse(context: context)
    }
}

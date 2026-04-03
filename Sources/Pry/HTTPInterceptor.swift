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

        // Filter check
        if let filter = filter, !host.contains(filter) {
            forwardRequest(context: context, host: host, port: port, head: head, body: body)
            return
        }

        // Log + store
        let logEntry = "\(head.method) \(head.uri) -> \(host):\(port)"
        let requestId = BodyPrinter.printRequestHead(head, host: host, port: port)
        BodyPrinter.printRequestBody(body)
        Config.appendLog(logEntry)

        // Mock check
        if let mockResponse = findMock(for: path, host: host) {
            respondWithMock(context: context, json: mockResponse, path: path, requestId: requestId)
            return
        }

        // Forward to real server
        forwardRequest(context: context, host: host, port: port, head: head, body: body, requestId: requestId)
    }

    private func findMock(for path: String, host: String) -> String? {
        let mocks = Config.loadMocks()
        for (mockKey, response) in mocks {
            if mockKey.contains(":") {
                // Domain-scoped mock: "domain.com:/path"
                let parts = mockKey.split(separator: ":", maxSplits: 1)
                let mockDomain = String(parts[0])
                let mockPath = String(parts[1])
                if host.contains(mockDomain) && path.hasPrefix(mockPath) {
                    return response
                }
            } else {
                // Simple path mock: "/api/login"
                if path.hasPrefix(mockKey) {
                    return response
                }
            }
        }
        return nil
    }

    private func respondWithMock(context: ChannelHandlerContext, json: String, path: String, requestId: Int) {
        BodyPrinter.printMock(path: path, json: json)
        BodyPrinter.storeResponse(requestId: requestId, statusCode: 200, headers: [("Content-Type", "application/json")], body: json, isMock: true)
        Config.appendLog("MOCK \(path) -> 200 OK")

        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "X-Pry-Mock", value: "true")

        let responseHead = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: json.utf8.count)
        buffer.writeString(json)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)

        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        context.close(promise: nil)
    }

    private func forwardRequest(context: ChannelHandlerContext, host: String, port: Int, head: HTTPRequestHead, body: ByteBuffer?, requestId: Int = 0) {
        let clientChannel = context.channel
        let group = context.eventLoop

        ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(ResponseForwarder(clientChannel: clientChannel, host: host, requestId: requestId))
                }
            }
            .connect(host: host, port: port)
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
    private var responseBody: ByteBuffer?
    private var statusCode: UInt = 0

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
            responseBody = context.channel.allocator.buffer(capacity: 0)
            let serverHead = NIOHTTP1.HTTPResponseHead(version: head.version, status: head.status, headers: head.headers)
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
        OutputBroker.shared.log(errText("!!! Response error from \(host): \(error)"))
        clientChannel.close(promise: nil)
        context.close(promise: nil)
    }
}

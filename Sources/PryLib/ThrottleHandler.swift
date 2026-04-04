import NIO
import NIOCore
import Foundation

/// NIO handler that throttles data throughput using a token bucket algorithm.
/// Simulates slow networks by limiting bytes per second and adding latency.
final class ThrottleHandler: ChannelDuplexHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let bytesPerSecond: Int
    private let latencyMs: Int
    private var tokensAvailable: Int
    private var lastRefillTime: UInt64

    init(config: ThrottleConfig) {
        self.bytesPerSecond = config.bytesPerSecond
        self.latencyMs = config.latencyMs
        self.tokensAvailable = config.bytesPerSecond
        self.lastRefillTime = DispatchTime.now().uptimeNanoseconds
    }

    // Inbound: data flowing from remote → client (download)
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        let bytes = buffer.readableBytes

        let delay = calculateDelay(bytes: bytes)
        if delay > 0 || latencyMs > 0 {
            let totalDelay = delay + latencyMs
            context.eventLoop.scheduleTask(in: .milliseconds(Int64(totalDelay))) {
                context.fireChannelRead(self.wrapInboundOut(buffer))
            }
        } else {
            context.fireChannelRead(wrapInboundOut(buffer))
        }
    }

    // Outbound: data flowing from client → remote (upload)
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        let bytes = buffer.readableBytes

        let delay = calculateDelay(bytes: bytes)
        if delay > 0 {
            context.eventLoop.scheduleTask(in: .milliseconds(Int64(delay))) {
                context.write(self.wrapOutboundOut(buffer), promise: promise)
            }
        } else {
            context.write(wrapOutboundOut(buffer), promise: promise)
        }
    }

    /// Token bucket algorithm: returns delay in ms if over budget, 0 if within budget
    private func calculateDelay(bytes: Int) -> Int {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsedNs = now - lastRefillTime
        let elapsedMs = Double(elapsedNs) / 1_000_000

        // Refill tokens based on elapsed time
        let refill = Int(elapsedMs / 1000.0 * Double(bytesPerSecond))
        tokensAvailable = min(tokensAvailable + refill, bytesPerSecond * 2) // Cap at 2s burst
        lastRefillTime = now

        // Consume tokens
        tokensAvailable -= bytes

        if tokensAvailable < 0 {
            // Calculate how long to wait for tokens to refill
            let deficit = -tokensAvailable
            let delayMs = Int(Double(deficit) / Double(bytesPerSecond) * 1000.0)
            return max(delayMs, 1)
        }
        return 0
    }
}

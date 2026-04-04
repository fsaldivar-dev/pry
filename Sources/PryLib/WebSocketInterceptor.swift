import NIO
import NIOCore
import Foundation

/// Intercepts WebSocket frames after upgrade, logs messages bidirectionally.
/// Sits between TLS/HTTP and GlueHandler to capture WebSocket traffic.
final class WebSocketInterceptor: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let host: String
    private let requestId: Int
    private var clientBuffer = Data()  // client → server (masked)
    private var serverBuffer = Data()  // server → client (unmasked)

    init(host: String, requestId: Int) {
        self.host = host
        self.requestId = requestId
    }

    // Server → Client
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        if let bytes = buffer.readBytes(length: buffer.readableBytes) {
            serverBuffer.append(contentsOf: bytes)
            parseFrames(from: &serverBuffer, direction: .serverToClient)
        }
        context.fireChannelRead(data)
    }

    // Client → Server
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        var buffer = unwrapOutboundIn(data)
        if let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) {
            clientBuffer.append(contentsOf: bytes)
            parseFrames(from: &clientBuffer, direction: .clientToServer)
        }
        context.write(wrapOutboundOut(buffer), promise: promise)
    }

    // MARK: - RFC 6455 Frame Parser

    private func parseFrames(from buffer: inout Data, direction: WSFrame.Direction) {
        while true {
            guard buffer.count >= 2 else { return }

            let byte0 = buffer[buffer.startIndex]
            let byte1 = buffer[buffer.startIndex + 1]

            let isFinal = (byte0 & 0x80) != 0
            let opcodeRaw = byte0 & 0x0F
            let isMasked = (byte1 & 0x80) != 0
            var payloadLength = UInt64(byte1 & 0x7F)

            var offset = 2

            // Extended payload length
            if payloadLength == 126 {
                guard buffer.count >= offset + 2 else { return }
                payloadLength = UInt64(buffer[buffer.startIndex + offset]) << 8 |
                                UInt64(buffer[buffer.startIndex + offset + 1])
                offset += 2
            } else if payloadLength == 127 {
                guard buffer.count >= offset + 8 else { return }
                payloadLength = 0
                for i in 0..<8 {
                    payloadLength = (payloadLength << 8) | UInt64(buffer[buffer.startIndex + offset + i])
                }
                offset += 8
            }

            // Masking key
            var maskingKey: [UInt8]?
            if isMasked {
                guard buffer.count >= offset + 4 else { return }
                maskingKey = Array(buffer[(buffer.startIndex + offset)..<(buffer.startIndex + offset + 4)])
                offset += 4
            }

            // Payload
            let totalLength = offset + Int(payloadLength)
            guard buffer.count >= totalLength else { return }

            var payload = Data(buffer[(buffer.startIndex + offset)..<(buffer.startIndex + totalLength)])

            // Unmask if needed
            if let mask = maskingKey {
                for i in 0..<payload.count {
                    payload[payload.startIndex + i] ^= mask[i % 4]
                }
            }

            let opcode = WSFrame.Opcode(rawValue: opcodeRaw) ?? .unknown
            let frame = WSFrame(
                direction: direction,
                opcode: opcode,
                payload: payload,
                isFinal: isFinal
            )

            logFrame(frame)
            RequestStore.shared.addWSFrame(requestId: requestId, frame: frame)

            // Consume parsed bytes
            buffer.removeFirst(totalLength)
        }
    }

    private func logFrame(_ frame: WSFrame) {
        let dir = frame.direction.rawValue
        let type = frame.opcode.label
        let size = frame.payload.count

        let preview: String
        if let text = frame.payloadText, frame.opcode == .text {
            let truncated = text.count > 100 ? String(text.prefix(100)) + "..." : text
            preview = truncated
        } else {
            preview = "[\(size) bytes]"
        }

        let msg = "🔌 WS \(dir) \(host) [\(type)] \(preview)"
        OutputBroker.shared.log(info(msg), type: .info)
    }
}

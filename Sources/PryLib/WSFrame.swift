import Foundation

/// Represents a single WebSocket message frame
public struct WSFrame {
    public enum Direction: String {
        case clientToServer = "↑"
        case serverToClient = "↓"
    }

    public enum Opcode: UInt8 {
        case continuation = 0x0
        case text = 0x1
        case binary = 0x2
        case close = 0x8
        case ping = 0x9
        case pong = 0xA
        case unknown = 0xFF

        public var label: String {
            switch self {
            case .continuation: return "continuation"
            case .text: return "text"
            case .binary: return "binary"
            case .close: return "close"
            case .ping: return "ping"
            case .pong: return "pong"
            case .unknown: return "unknown"
            }
        }
    }

    public let timestamp: Date
    public let direction: Direction
    public let opcode: Opcode
    public let payload: Data
    public let isFinal: Bool

    public var payloadText: String? {
        String(data: payload, encoding: .utf8)
    }

    public init(timestamp: Date = Date(), direction: Direction, opcode: Opcode, payload: Data, isFinal: Bool = true) {
        self.timestamp = timestamp
        self.direction = direction
        self.opcode = opcode
        self.payload = payload
        self.isFinal = isFinal
    }
}

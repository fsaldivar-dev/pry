import Foundation

public struct ThrottleConfig {
    public let bytesPerSecond: Int
    public let latencyMs: Int
    public let label: String

    public init(bytesPerSecond: Int, latencyMs: Int, label: String = "Custom") {
        self.bytesPerSecond = bytesPerSecond
        self.latencyMs = latencyMs
        self.label = label
    }
}

public struct NetworkThrottle {
    public private(set) static var current: ThrottleConfig?

    public static func enable(_ config: ThrottleConfig) {
        current = config
        Config.set("throttle_bps", value: "\(config.bytesPerSecond)")
        Config.set("throttle_latency", value: "\(config.latencyMs)")
    }

    public static func disable() {
        current = nil
        Config.set("throttle_bps", value: "")
        Config.set("throttle_latency", value: "")
    }

    public static func preset(_ name: String) -> ThrottleConfig? {
        switch name.lowercased() {
        case "3g":
            return ThrottleConfig(bytesPerSecond: 750_000, latencyMs: 200, label: "3G")
        case "slow":
            return ThrottleConfig(bytesPerSecond: 100_000, latencyMs: 500, label: "Slow")
        case "edge", "2g":
            return ThrottleConfig(bytesPerSecond: 50_000, latencyMs: 800, label: "EDGE")
        case "wifi":
            return ThrottleConfig(bytesPerSecond: 5_000_000, latencyMs: 10, label: "WiFi")
        default:
            return nil
        }
    }
}

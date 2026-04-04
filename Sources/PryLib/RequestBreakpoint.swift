import NIO
import NIOCore
import NIOHTTP1
import Foundation

/// Action to take when resuming a paused request
public enum BreakpointAction {
    case resume
    case modify(headers: [(String, String)]?, body: String?)
    case cancel
}

/// A request that has been paused at a breakpoint
public struct PausedRequest {
    public let id: Int
    public let method: String
    public let url: String
    public let host: String
    public let headers: [(String, String)]
    public let body: String?
    public let timestamp: Date

    let promise: EventLoopPromise<BreakpointAction>
}

/// Coordinates request pausing and resuming between handlers and TUI
public class RequestBreakpointManager {
    public static let shared = RequestBreakpointManager()

    private let queue = DispatchQueue(label: "pry.breakpoint.manager")
    private var pausedRequests: [PausedRequest] = []
    public var onPause: (() -> Void)?

    /// Pause a request — returns a future that resolves when the user takes action
    func pause(
        id: Int,
        head: HTTPRequestHead,
        body: ByteBuffer?,
        host: String,
        eventLoop: EventLoop
    ) -> EventLoopFuture<BreakpointAction> {
        let promise = eventLoop.makePromise(of: BreakpointAction.self)

        var bodyStr: String?
        if var buf = body, buf.readableBytes > 0 {
            bodyStr = buf.readString(length: buf.readableBytes)
        }

        let paused = PausedRequest(
            id: id,
            method: "\(head.method)",
            url: head.uri,
            host: host,
            headers: head.headers.map { ($0.name, $0.value) },
            body: bodyStr,
            timestamp: Date(),
            promise: promise
        )

        queue.sync {
            pausedRequests.append(paused)
        }

        OutputBroker.shared.log(
            errText("⏸️ BREAKPOINT: \(head.method) \(head.uri) — esperando acción"),
            type: .info
        )

        onPause?()
        return promise.futureResult
    }

    /// Get all currently paused requests
    public func getPaused() -> [PausedRequest] {
        queue.sync { pausedRequests }
    }

    /// Resume a paused request with an action
    public func resume(id: Int, action: BreakpointAction) {
        queue.sync {
            if let idx = pausedRequests.firstIndex(where: { $0.id == id }) {
                let paused = pausedRequests.remove(at: idx)
                paused.promise.succeed(action)
            }
        }
    }

    /// Resume all paused requests
    public func resumeAll() {
        queue.sync {
            for paused in pausedRequests {
                paused.promise.succeed(.resume)
            }
            pausedRequests.removeAll()
        }
    }

    /// Count of paused requests
    public var pausedCount: Int {
        queue.sync { pausedRequests.count }
    }
}

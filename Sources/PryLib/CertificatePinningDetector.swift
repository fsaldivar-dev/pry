import NIO
import NIOCore
import NIOTLS
import Foundation

/// Detects probable certificate pinning by monitoring client behavior
/// after TLS handshake with our MITM certificate.
///
/// Heuristic: if the client closes the connection without sending any
/// HTTP data after completing the TLS handshake, the app likely rejected
/// our certificate due to certificate pinning.
final class CertificatePinningDetector: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer

    private let host: String
    private var handshakeComplete = false
    private var receivedHTTPData = false
    private var reported = false

    init(host: String) {
        self.host = host
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let tlsEvent = event as? TLSUserEvent, case .handshakeCompleted = tlsEvent {
            handshakeComplete = true
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        receivedHTTPData = true
        context.fireChannelRead(data)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if handshakeComplete && !receivedHTTPData && !reported {
            reported = true
            let msg = "📌 \(host) — posible certificate pinning detectado (conexión cerrada sin datos HTTP)"
            OutputBroker.shared.log(errText(msg), type: .error)
            Config.appendLog("PINNING \(host)")

            let id = RequestStore.shared.addRequest(
                method: "CONNECT",
                url: host,
                host: host,
                appIcon: "📌",
                appName: "pinned",
                headers: [],
                body: nil
            )
            RequestStore.shared.updateResponse(
                id: id,
                statusCode: 0,
                headers: [],
                body: "Certificate pinning detected — app rejected MITM certificate",
                isMock: false
            )
            RequestStore.shared.markPinned(id: id)
        }
        context.fireChannelInactive()
    }
}

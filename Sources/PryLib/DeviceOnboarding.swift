import Foundation
import NIO
import NIOHTTP1

/// Manages device onboarding — network discovery, QR generation, and HTTP server for setup page.
public struct DeviceOnboarding {

    /// Detect local IP addresses on network interfaces (en0, en1, etc.)
    public static func localIPAddresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return addresses }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family

            if family == UInt8(AF_INET) {  // IPv4 only
                let name = String(cString: interface.ifa_name)
                if name.hasPrefix("en") || name.hasPrefix("bridge") {  // Wi-Fi, Ethernet, bridge
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    #if os(Linux)
                    let addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                    #else
                    let addrLen = socklen_t(interface.ifa_addr.pointee.sa_len)
                    #endif
                    getnameinfo(interface.ifa_addr, addrLen,
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    let address = String(cString: hostname)
                    if !address.isEmpty && address != "127.0.0.1" {
                        addresses.append(address)
                    }
                }
            }

            guard let next = interface.ifa_next else { break }
            ptr = next
        }

        return addresses
    }

    /// Generate QR payload JSON for device configuration.
    public static func generateQRPayload(proxyHost: String, proxyPort: Int) -> String {
        return "{\"proxy\":\"\(proxyHost):\(proxyPort)\",\"host\":\"\(proxyHost)\",\"port\":\(proxyPort),\"setup\":\"http://\(proxyHost):8081\"}"
    }

    /// Generate the onboarding HTML page.
    public static func generateHTML(proxyHost: String, proxyPort: Int) -> String {
        let caPath = CertificateAuthority.caCertPath
        let caExists = FileManager.default.fileExists(atPath: caPath)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Pry — Device Setup</title>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #0D1117; color: #E6EDF3; min-height: 100vh; padding: 24px; }
                .container { max-width: 600px; margin: 0 auto; }
                h1 { font-size: 28px; margin-bottom: 8px; }
                .subtitle { color: #8B949E; margin-bottom: 32px; }
                .card { background: #161B22; border: 1px solid #30363D; border-radius: 12px; padding: 24px; margin-bottom: 16px; }
                .step-number { display: inline-block; width: 28px; height: 28px; background: #238636; border-radius: 50%; text-align: center; line-height: 28px; font-weight: 600; font-size: 14px; margin-right: 12px; }
                .step-title { font-size: 18px; font-weight: 600; margin-bottom: 8px; }
                .step-detail { color: #8B949E; font-size: 14px; line-height: 1.6; }
                code { background: #1F2937; padding: 2px 6px; border-radius: 4px; font-size: 13px; color: #79C0FF; }
                .info-box { background: #161B22; border: 1px solid #30363D; border-radius: 8px; padding: 16px; margin-top: 24px; text-align: center; }
                .info-label { color: #8B949E; font-size: 12px; text-transform: uppercase; letter-spacing: 1px; }
                .info-value { font-size: 20px; font-weight: 600; margin-top: 4px; color: #58A6FF; }
                .btn { display: inline-block; background: #238636; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none; font-weight: 600; margin-top: 12px; }
                .btn:hover { background: #2EA043; }
                .qr-placeholder { width: 200px; height: 200px; background: white; border-radius: 8px; margin: 16px auto; display: flex; align-items: center; justify-content: center; color: #0D1117; font-size: 12px; text-align: center; padding: 8px; }
                .status { display: inline-block; width: 8px; height: 8px; background: #238636; border-radius: 50%; margin-right: 8px; animation: pulse 2s infinite; }
                @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Pry</h1>
                <p class="subtitle">Device Setup</p>

                <div class="info-box">
                    <div class="info-label">Proxy Address</div>
                    <div class="info-value">\(proxyHost):\(proxyPort)</div>
                    <div style="margin-top: 8px;"><span class="status"></span>Proxy running</div>
                </div>

                <div style="text-align: center; margin: 24px 0;">
                    <div class="qr-placeholder">
                        Scan with camera app<br><br>
                        <strong>\(proxyHost):\(proxyPort)</strong>
                    </div>
                </div>

                <div class="card">
                    <div class="step-title"><span class="step-number">1</span>Configure Proxy</div>
                    <div class="step-detail">
                        <strong>iOS:</strong> Settings &rarr; Wi-Fi &rarr; tap your network &rarr; Configure Proxy &rarr; Manual<br>
                        Server: <code>\(proxyHost)</code> Port: <code>\(proxyPort)</code><br><br>
                        <strong>Android:</strong> Settings &rarr; Wi-Fi &rarr; long-press network &rarr; Modify &rarr; Advanced &rarr; Proxy: Manual<br>
                        Hostname: <code>\(proxyHost)</code> Port: <code>\(proxyPort)</code><br><br>
                        <strong>macOS:</strong> System Settings &rarr; Network &rarr; Wi-Fi &rarr; Details &rarr; Proxies<br>
                        HTTP &amp; HTTPS Proxy: <code>\(proxyHost):\(proxyPort)</code>
                    </div>
                </div>

                <div class="card">
                    <div class="step-title"><span class="step-number">2</span>Install Certificate</div>
                    <div class="step-detail">
                        Download and install the Pry CA certificate to intercept HTTPS traffic.\(caExists ? "" : "<br><em>CA certificate not found. Run <code>pry start</code> first.</em>")<br><br>
                        <strong>iOS:</strong> Download &rarr; Settings &rarr; General &rarr; VPN &amp; Device Management &rarr; Install &rarr; then Settings &rarr; General &rarr; About &rarr; Certificate Trust Settings &rarr; Enable<br><br>
                        <strong>Android:</strong> Download &rarr; Settings &rarr; Security &rarr; Install from storage<br><br>
                        <strong>macOS:</strong> Download &rarr; double-click &rarr; add to Keychain &rarr; trust
                    </div>
                    \(caExists ? "<a href=\"/ca.pem\" class=\"btn\">Download CA Certificate</a>" : "")
                </div>

                <div class="card">
                    <div class="step-title"><span class="step-number">3</span>Verify</div>
                    <div class="step-detail">
                        Open any app or browser on your device. Traffic should appear in Pry.<br>
                        If HTTPS sites show certificate errors, make sure you completed step 2.
                    </div>
                </div>
            </div>
        </body>
        </html>
        """
    }

    /// Start the onboarding HTTP server on the given port.
    /// Returns the Channel for lifecycle management.
    public static func startServer(port: Int = 8081, proxyPort: Int, group: EventLoopGroup) throws -> Channel {
        let ip = localIPAddresses().first ?? "localhost"
        let html = generateHTML(proxyHost: ip, proxyPort: proxyPort)
        let caPath = CertificateAuthority.caCertPath

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 64)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(ByteToMessageHandler(HTTPRequestDecoder()))
                    try channel.pipeline.syncOperations.addHandler(HTTPResponseEncoder())
                    try channel.pipeline.syncOperations.addHandler(OnboardingHandler(html: html, caPath: caPath))
                }
            }

        let channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
        print("Device setup page: http://\(ip):\(port)")
        return channel
    }
}

// MARK: - NIO Handler

/// Simple HTTP handler that serves the onboarding page and CA certificate.
private final class OnboardingHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let html: String
    private let caPath: String

    init(html: String, caPath: String) {
        self.html = html
        self.caPath = caPath
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        guard case .head(let head) = part else { return }

        if head.uri == "/ca.pem" {
            serveCACert(context: context, version: head.version)
        } else {
            serveHTML(context: context, version: head.version)
        }
    }

    private func serveHTML(context: ChannelHandlerContext, version: HTTPVersion) {
        let data = html.data(using: .utf8)!
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/html; charset=utf-8")
        headers.add(name: "Content-Length", value: "\(data.count)")
        let head = HTTPResponseHead(version: version, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func serveCACert(context: ChannelHandlerContext, version: HTTPVersion) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: caPath)) else {
            let head = HTTPResponseHead(version: version, status: .notFound)
            context.write(wrapOutboundOut(.head(head)), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            return
        }
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/x-pem-file")
        headers.add(name: "Content-Disposition", value: "attachment; filename=\"pry-ca.pem\"")
        headers.add(name: "Content-Length", value: "\(data.count)")
        let head = HTTPResponseHead(version: version, status: .ok, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
}

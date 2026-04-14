import SwiftUI
import PryKit
import PryLib
import NIO

@available(macOS 14, *)
@MainActor
struct DeviceSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProxyManager.self) private var proxy

    @State private var serverChannel: Channel?
    @State private var isServerRunning = false

    private var localIP: String {
        DeviceOnboarding.localIPAddresses().first ?? "unknown"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Device Setup")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    stopServer()
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            VStack(spacing: 16) {
                // IP + Port info
                VStack(spacing: 4) {
                    Text("Proxy Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(localIP):\(String(proxy.port))")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(PryTheme.accent)
                        .textSelection(.enabled)
                }

                // Setup page URL
                if isServerRunning {
                    VStack(spacing: 4) {
                        Text("Setup Page")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("http://\(localIP):8081")
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundStyle(PryTheme.success)
                            .textSelection(.enabled)
                    }

                    Text("Open this URL on your device to configure it")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Button("Open in Browser") {
                        if let url = URL(string: "http://\(localIP):8081") {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    Button("Stop Server") {
                        stopServer()
                    }
                    .tint(.red)
                } else {
                    Text("Start the setup server so devices on your network\ncan configure the proxy automatically.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        startServer()
                    } label: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Start Setup Server")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!proxy.isRunning)

                    if !proxy.isRunning {
                        Text("Start the proxy first")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Divider()

                // Instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("MANUAL SETUP")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PryTheme.textTertiary)
                        .tracking(1.5)

                    Text("1. On your device, go to Wi-Fi settings")
                    Text("2. Set HTTP Proxy to: \(localIP):\(String(proxy.port))")
                    Text("3. Download CA certificate from the setup page")
                    Text("4. Install and trust the certificate")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)

            Spacer()
        }
    }

    private func startServer() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            let channel = try DeviceOnboarding.startServer(port: 8081, proxyPort: proxy.port, group: group)
            serverChannel = channel
            isServerRunning = true
        } catch {
            print("Failed to start setup server: \(error)")
        }
    }

    private func stopServer() {
        try? serverChannel?.close().wait()
        serverChannel = nil
        isServerRunning = false
    }
}

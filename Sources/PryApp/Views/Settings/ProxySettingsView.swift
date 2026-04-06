import SwiftUI
import PryKit
import PryLib

@available(macOS 14, *)
@MainActor
struct ProxySettingsView: View {
    @Environment(ProxyManager.self) private var proxy
    @State private var portText: String = ""
    @State private var portError: String?
    @AppStorage("pry.autoStart") private var autoStart = false

    var body: some View {
        Form {
            Section("Proxy Server") {
                LabeledContent("Status") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(proxy.isRunning ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(proxy.isRunning ? "Running" : "Stopped")
                    }
                }

                HStack {
                    LabeledContent("Port") {
                        TextField("8080", text: $portText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onChange(of: portText) { validatePort() }
                    }
                    if let portError {
                        Text(portError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Button("Apply Port") {
                    applyPort()
                }
                .disabled(portError != nil || portText.isEmpty)
            }

            Section("System Proxy") {
                HStack {
                    Toggle("Configure system proxy automatically", isOn: .constant(proxy.systemProxyEnabled))
                    if proxy.systemProxyEnabled {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Text("When enabled, macOS routes HTTP/HTTPS traffic through Pry automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let service = SystemProxy.activeNetworkService() {
                    LabeledContent("Network Interface", value: service)
                        .font(.caption)
                }
            }

            Section("Startup") {
                Toggle("Auto-start proxy on launch", isOn: $autoStart)
                Text("Proxy will start automatically when PryApp opens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Network") {
                LabeledContent("Proxy URL") {
                    Text("http://localhost:\(proxy.port)")
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }

                Button("Copy Proxy URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("http://localhost:\(proxy.port)", forType: .string)
                }

                Text("Configure your app or browser to use this proxy address.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            portText = "\(proxy.port)"
        }
    }

    private func validatePort() {
        guard let port = Int(portText) else {
            portError = "Must be a number"
            return
        }
        guard port >= 1024, port <= 65535 else {
            portError = "Must be 1024–65535"
            return
        }
        portError = nil
    }

    private func applyPort() {
        guard let port = Int(portText), portError == nil else { return }
        Config.set("port", value: "\(port)")
        proxy.port = port
    }
}

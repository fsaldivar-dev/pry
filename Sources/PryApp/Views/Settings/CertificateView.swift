import SwiftUI
import PryLib

@available(macOS 14, *)
@MainActor
struct CertificateView: View {
    @State private var caExists = false
    @State private var trustStatus = "Checking..."
    @State private var isCheckingTrust = false

    var body: some View {
        Form {
            Section("Pry Certificate Authority") {
                LabeledContent("CA Directory") {
                    Text(CertificateAuthority.caDir)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Certificate") {
                    if caExists {
                        Label("Generated", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Generated", systemImage: "xmark.circle")
                            .foregroundStyle(.orange)
                    }
                }

                LabeledContent("Keychain Trust") {
                    Text(trustStatus)
                        .foregroundStyle(trustStatus == "Trusted" ? .green : .secondary)
                }
            }

            Section("Actions") {
                if caExists {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(
                            CertificateAuthority.caCertPath,
                            inFileViewerRootedAtPath: CertificateAuthority.caDir
                        )
                    }

                    Button("Copy Certificate Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(CertificateAuthority.caCertPath, forType: .string)
                    }
                } else {
                    Text("Start the proxy to generate the CA certificate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Instructions") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("For HTTPS interception, the CA must be trusted:")
                        .font(.caption)
                    Text("1. Open Keychain Access")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("2. Drag the pry-ca.pem file into the System keychain")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("3. Double-click the certificate → Trust → Always Trust")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("")
                    Text("For iOS Simulator: run `pry trust` in Terminal")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { checkCA() }
    }

    private func checkCA() {
        caExists = FileManager.default.fileExists(atPath: CertificateAuthority.caCertPath)
        if caExists {
            checkTrustStatus()
        } else {
            trustStatus = "N/A — certificate not generated"
        }
    }

    private func checkTrustStatus() {
        // Check if CA is in the trusted certs via security CLI
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["verify-cert", "-c", CertificateAuthority.caCertPath]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try? process.run()
            process.waitUntilExit()
            let status = process.terminationStatus == 0 ? "Trusted" : "Not Trusted"
            await MainActor.run {
                trustStatus = status
            }
        }
    }
}

import SwiftUI
import PryLib

@available(macOS 14, *)
@MainActor
struct CertificateView: View {
    @State private var caExists = false
    @State private var trustStatus = "Checking..."
    @State private var isCheckingTrust = false
    @State private var isTrusting = false
    @State private var trustError: String?

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
                    // One-click trust button
                    HStack {
                        Button {
                            trustCA()
                        } label: {
                            HStack(spacing: 6) {
                                if isTrusting {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(trustStatus == "Trusted" ? "Revoke Trust" : "Trust Certificate")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(trustStatus == "Trusted" ? .red : .green)
                        .disabled(isTrusting)
                    }

                    if let err = trustError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Divider()

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
                    Text("• Click \"Trust Certificate\" above (may prompt for admin password)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("• Or manually: Keychain Access → drag pry-ca.pem → Always Trust")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("• For iOS Simulator: run `pry trust` in Terminal")
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
        isCheckingTrust = true
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
                isCheckingTrust = false
            }
        }
    }

    private func trustCA() {
        isTrusting = true
        trustError = nil
        let caPath = CertificateAuthority.caCertPath
        Task.detached {
            // Attempt 1: System keychain (requires admin — triggers macOS auth dialog)
            let sys = Process()
            sys.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            sys.arguments = ["add-trusted-cert", "-d", "-r", "trustRoot",
                             "-k", "/Library/Keychains/System.keychain", caPath]
            sys.standardOutput = Pipe()
            sys.standardError = Pipe()
            try? sys.run()
            sys.waitUntilExit()

            if sys.terminationStatus == 0 {
                await MainActor.run {
                    isTrusting = false
                    trustStatus = "Trusted"
                }
                return
            }

            // Fallback: user login keychain (no admin required)
            let loginKeychain = NSString(string: "~/Library/Keychains/login.keychain-db")
                .expandingTildeInPath
            let user = Process()
            user.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            user.arguments = ["add-trusted-cert", "-r", "trustRoot",
                              "-k", loginKeychain, caPath]
            user.standardOutput = Pipe()
            let errPipe = Pipe()
            user.standardError = errPipe
            try? user.run()
            user.waitUntilExit()

            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            await MainActor.run {
                isTrusting = false
                if user.terminationStatus == 0 {
                    trustStatus = "Trusted"
                } else {
                    let msg = errMsg?.isEmpty == false ? errMsg : "Failed to trust certificate"
                    trustError = msg
                    checkTrustStatus()
                }
            }
        }
    }
}

import SwiftUI

/// UI para gestionar DNS overrides. Consume `DNSOverridesStore` via
/// `AppCore` inyectado en `@Environment`.
@available(macOS 14, *)
struct DNSOverridesView: View {
    @Environment(AppCore.self) private var core

    @State private var newDomain: String = ""
    @State private var newIP: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header con inputs para agregar.
            HStack {
                TextField("Domain (ej. api.example.com)", text: $newDomain)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addCurrent() }
                TextField("IP (ej. 127.0.0.1)", text: $newIP)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit { addCurrent() }
                Button("Add") { addCurrent() }
                    .disabled(!canAdd)
            }
            .padding()

            Divider()

            // Lista de overrides.
            if core.dnsOverrides.overrides.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No hay DNS overrides")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(core.dnsOverrides.overrides, id: \.domain) { override in
                        HStack {
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundStyle(.blue.opacity(0.85))
                            Text(override.domain)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(override.ip)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Button {
                                core.dnsOverrides.remove(domain: override.domain)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("DNS Overrides")
    }

    private var canAdd: Bool {
        let d = newDomain.trimmingCharacters(in: .whitespaces)
        let i = newIP.trimmingCharacters(in: .whitespaces)
        return !d.isEmpty && !i.isEmpty && i.contains(".")
    }

    @MainActor
    private func addCurrent() {
        let domain = newDomain.trimmingCharacters(in: .whitespaces)
        let ip = newIP.trimmingCharacters(in: .whitespaces)
        guard !domain.isEmpty, !ip.isEmpty else { return }
        core.dnsOverrides.add(domain: domain, ip: ip)
        newDomain = ""
        newIP = ""
    }
}

// Previews usan PreviewProvider (no el macro #Preview) porque el package
// target es macOS 13 y el macro no soporta `@available(macOS 14, *)`.
@available(macOS 14, *)
struct DNSOverridesView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DNSOverridesView()
                .environment(AppCore.preview())
                .previewDisplayName("empty")

            DNSOverridesView()
                .environment(AppCore.previewWithDNSOverrides([
                    ("api.example.com", "127.0.0.1"),
                    ("staging.acme.io", "10.0.0.42"),
                    ("cdn.local", "192.168.1.50")
                ]))
                .previewDisplayName("with data")
        }
        .frame(width: 520, height: 400)
    }
}

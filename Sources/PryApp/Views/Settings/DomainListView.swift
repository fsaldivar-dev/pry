import SwiftUI
import PryKit
import PryLib

@available(macOS 14, *)
@MainActor
struct DomainListView: View {
    @Environment(ProxyManager.self) private var proxy
    @State private var newDomain = ""
    @State private var showingScanner = false
    @State private var scannedDomains: [String] = []
    @State private var showScannedSheet = false

    var body: some View {
        Form {
            Section("Intercepted Domains") {
                if proxy.domains.isEmpty {
                    Text("No domains in watchlist")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    List {
                        ForEach(proxy.domains, id: \.self) { domain in
                            HStack {
                                Image(systemName: "globe")
                                    .foregroundStyle(.secondary)
                                Text(domain)
                                    .font(.system(size: 12, design: .monospaced))
                                Spacer()
                                Button {
                                    proxy.removeDomain(domain)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .frame(minHeight: 120)
                }

                HStack {
                    TextField("Add domain", text: $newDomain, prompt: Text("api.example.com"))
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addDomain() }
                    Button("Add") { addDomain() }
                        .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Auto-discover") {
                HStack {
                    Button("Scan Project...") { showingScanner = true }
                    Text("Find domains in your source code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fileImporter(
                    isPresented: $showingScanner,
                    allowedContentTypes: [.folder]
                ) { result in
                    if case .success(let url) = result {
                        let discovered = ProjectScanner.scan(directory: url.path)
                        if discovered.isEmpty {
                            scannedDomains = []
                        } else {
                            scannedDomains = discovered.filter { !proxy.domains.contains($0) }
                        }
                        showScannedSheet = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showScannedSheet) {
            ScannedDomainsSheet(domains: scannedDomains) { selected in
                for domain in selected {
                    proxy.addDomain(domain)
                }
            }
        }
    }

    private func addDomain() {
        let domain = newDomain.trimmingCharacters(in: .whitespaces).lowercased()
        guard !domain.isEmpty else { return }
        proxy.addDomain(domain)
        newDomain = ""
    }
}

@available(macOS 14, *)
private struct ScannedDomainsSheet: View {
    let domains: [String]
    let onAdd: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Discovered Domains")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add Selected") {
                    onAdd(Array(selected))
                    dismiss()
                }
                .disabled(selected.isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            if domains.isEmpty {
                ContentUnavailableView(
                    "No Domains Found",
                    systemImage: "magnifyingglass",
                    description: Text("No new domains were found in the project")
                )
            } else {
                List(domains, id: \.self, selection: $selected) { domain in
                    Text(domain)
                        .font(.system(size: 12, design: .monospaced))
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear { selected = Set(domains) }
    }
}

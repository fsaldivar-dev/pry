import SwiftUI
import PryLib

@available(macOS 14, *)
@MainActor
struct RulesSettingsView: View {
    @State private var headerRules: [HeaderRewrite.Rule] = []
    @State private var mapLocalRules: [MapLocal.MapRule] = []
    @State private var mapRemoteRules: [MapRemote.RedirectRule] = []

    // New rule fields
    @State private var newHeaderName = ""
    @State private var newHeaderValue = ""
    @State private var newMapRegex = ""
    @State private var newMapFile = ""
    @State private var newRedirectSrc = ""
    @State private var newRedirectDst = ""

    // Validation errors
    @State private var regexError: String?
    @State private var fileError: String?
    @State private var hostError: String?

    var body: some View {
        Form {
            Section("Header Rewrite Rules") {
                if headerRules.isEmpty {
                    Text("No header rules").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(headerRules.enumerated()), id: \.offset) { _, rule in
                        HStack {
                            Text(rule.name)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.accentColor)
                            Text(rule.value ?? "")
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                            Button {
                                HeaderRewrite.removeRule(name: rule.name)
                                reload()
                            } label: {
                                Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                HStack {
                    TextField("Header", text: $newHeaderName)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 150)
                    TextField("Value", text: $newHeaderValue)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let name = newHeaderName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty, Self.isValidHeaderName(name) else { return }
                        HeaderRewrite.addRule(name: name, value: newHeaderValue)
                        newHeaderName = ""; newHeaderValue = ""
                        reload()
                    }
                    .disabled(newHeaderName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Map Local (URL → File)") {
                if mapLocalRules.isEmpty {
                    Text("No map local rules").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(mapLocalRules.enumerated()), id: \.offset) { _, rule in
                        VStack(alignment: .leading) {
                            Text(rule.regex).font(.system(size: 11, design: .monospaced))
                            Text("→ \(rule.filePath)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                VStack(alignment: .leading) {
                    HStack {
                        TextField("URL regex", text: $newMapRegex)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: newMapRegex) { validateRegex() }
                        TextField("File path", text: $newMapFile)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: newMapFile) { validateFilePath() }
                        Button("Add") {
                            guard validateMapLocalInputs() else { return }
                            MapLocal.save(regex: newMapRegex, filePath: newMapFile)
                            newMapRegex = ""; newMapFile = ""
                            regexError = nil; fileError = nil
                            reload()
                        }
                        .disabled(newMapRegex.isEmpty || newMapFile.isEmpty ||
                                  regexError != nil || fileError != nil)
                    }
                    if let regexError {
                        Text(regexError).font(.caption2).foregroundStyle(.red)
                    }
                    if let fileError {
                        Text(fileError).font(.caption2).foregroundStyle(.red)
                    }
                }
            }

            Section("Map Remote (Host → Host)") {
                if mapRemoteRules.isEmpty {
                    Text("No redirect rules").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(mapRemoteRules.enumerated()), id: \.offset) { _, rule in
                        HStack {
                            Text(rule.sourceHost)
                                .font(.system(size: 11, design: .monospaced))
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            Text(rule.targetHost)
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                }
                VStack(alignment: .leading) {
                    HStack {
                        TextField("Source host", text: $newRedirectSrc)
                            .textFieldStyle(.roundedBorder)
                        TextField("Target host", text: $newRedirectDst)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            let src = newRedirectSrc.trimmingCharacters(in: .whitespaces).lowercased()
                            let dst = newRedirectDst.trimmingCharacters(in: .whitespaces).lowercased()
                            guard Self.isValidHostname(src), Self.isValidHostname(dst) else {
                                hostError = "Invalid hostname format"
                                return
                            }
                            MapRemote.save(sourceHost: src, targetHost: dst)
                            newRedirectSrc = ""; newRedirectDst = ""
                            hostError = nil
                            reload()
                        }
                        .disabled(newRedirectSrc.isEmpty || newRedirectDst.isEmpty)
                    }
                    if let hostError {
                        Text(hostError).font(.caption2).foregroundStyle(.red)
                    }
                }
            }

            Section {
                Button("Clear All Rules", role: .destructive) {
                    HeaderRewrite.clear()
                    MapLocal.clear()
                    MapRemote.clear()
                    reload()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { reload() }
    }

    private func reload() {
        headerRules = HeaderRewrite.loadAll()
        mapLocalRules = MapLocal.loadAll()
        mapRemoteRules = MapRemote.loadAll()
    }

    // MARK: - Input Validation

    /// Validate HTTP header name: alphanumeric + hyphens only (RFC 7230)
    private static func isValidHeaderName(_ name: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        return !name.isEmpty && name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Validate regex compiles without error
    private func validateRegex() {
        let pattern = newMapRegex.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { regexError = nil; return }
        do {
            _ = try NSRegularExpression(pattern: pattern)
            regexError = nil
        } catch {
            regexError = "Invalid regex: \(error.localizedDescription)"
        }
    }

    /// Validate file path: must be absolute, no traversal, file must exist
    private func validateFilePath() {
        let path = newMapFile.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { fileError = nil; return }
        // Must be absolute path
        guard path.hasPrefix("/") else {
            fileError = "Must be an absolute path (starting with /)"
            return
        }
        // Reject path traversal
        let resolved = (path as NSString).standardizingPath
        guard !resolved.contains("..") else {
            fileError = "Path traversal not allowed"
            return
        }
        // File must exist
        guard FileManager.default.fileExists(atPath: resolved) else {
            fileError = "File does not exist"
            return
        }
        fileError = nil
    }

    /// Combined validation for Map Local inputs
    private func validateMapLocalInputs() -> Bool {
        validateRegex()
        validateFilePath()
        return regexError == nil && fileError == nil
    }

    /// Validate hostname: alphanumeric, dots, hyphens, optional port
    private static func isValidHostname(_ host: String) -> Bool {
        // hostname:port or hostname
        let parts = host.split(separator: ":", maxSplits: 1)
        let hostname = String(parts[0])
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-*"))
        guard !hostname.isEmpty,
              hostname.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              !hostname.contains("..") else { return false }
        // Validate port if present
        if parts.count == 2 {
            guard let port = Int(parts[1]), port > 0, port <= 65535 else { return false }
        }
        return true
    }
}

import SwiftUI
import PryLib

@available(macOS 14, *)
struct RulesEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rulesText = ""
    @State private var statusMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Rules Editor")
                    .font(.headline)
                Spacer()
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Editor
            TextEditor(text: $rulesText)
                .font(.system(size: 12, design: .monospaced))
                .padding(4)

            Divider()

            // Actions
            HStack {
                Button("Load from File...") {
                    loadFromFile()
                }
                Spacer()
                Button("Clear") {
                    rulesText = ""
                    RuleEngine.clear()
                    statusMessage = "Rules cleared"
                }
                Button("Apply") {
                    applyRules()
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
    }

    private func applyRules() {
        let parsed = RuleEngine.parse(content: rulesText)
        RuleEngine.loadRules(parsed)
        statusMessage = "\(parsed.count) rule(s) applied"
    }

    private func loadFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                rulesText = try String(contentsOf: url, encoding: .utf8)
                statusMessage = "Loaded \(url.lastPathComponent)"
            } catch {
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }
}

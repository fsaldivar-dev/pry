import SwiftUI
import PryLib

@available(macOS 14, *)
@MainActor
struct RulesEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rulesText: String = ""
    @State private var parseResult: ParseResult = .empty
    @State private var validationTask: Task<Void, Never>?

    private let rulesFile = ".pryrules"

    enum ParseResult: Equatable {
        case empty
        case valid(count: Int)
        case error(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Rules Editor")
                    .font(.headline)
                Spacer()

                switch parseResult {
                case .empty:
                    EmptyView()
                case .valid(let count):
                    Label("\(count) rule(s) valid", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .error(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }

                Button("Apply") { applyRules() }
                    .disabled(parseResult == .empty)

                Button("Clear") {
                    RuleEngine.clear()
                    rulesText = ""
                    parseResult = .empty
                }

                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            TextEditor(text: $rulesText)
                .font(.system(size: 12, design: .monospaced))
                .onChange(of: rulesText) {
                    validationTask?.cancel()
                    validationTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        validateRules()
                    }
                }

            Divider()

            // Current active rules
            HStack {
                Text("Active rules: \(RuleEngine.all().count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.bar)
        }
        .onAppear { loadExistingRules() }
    }

    private func loadExistingRules() {
        if let content = try? String(contentsOfFile: rulesFile, encoding: .utf8) {
            rulesText = content
            validateRules()
        } else {
            rulesText = """
            # Pry Rules — example
            # match /api/* {
            #   add-header X-Debug true
            # }
            """
        }
    }

    private func validateRules() {
        let text = rulesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.allSatisfy({ $0 == "#" || $0.isNewline || $0.isWhitespace }) else {
            parseResult = .empty
            return
        }
        let rules = RuleEngine.parse(content: rulesText)
        if rules.isEmpty {
            parseResult = .error("No valid rules parsed")
        } else {
            parseResult = .valid(count: rules.count)
        }
    }

    private func applyRules() {
        let rules = RuleEngine.parse(content: rulesText)
        RuleEngine.loadRules(rules)
        // Save to file
        try? rulesText.write(toFile: rulesFile, atomically: true, encoding: .utf8)
    }
}

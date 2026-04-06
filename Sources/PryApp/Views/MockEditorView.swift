import SwiftUI
import PryKit

@available(macOS 14, *)
@MainActor
struct MockEditorView: View {
    @Environment(MockManager.self) private var mockManager
    @Environment(\.dismiss) private var dismiss

    let existingPath: String?

    @State private var urlPattern: String = ""
    @State private var responseBody: String = "{}"
    @State private var jsonError: String?

    var isEditing: Bool { existingPath != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Mock" : "New Mock")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") { saveMock() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(urlPattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            Divider()

            Form {
                Section("Endpoint") {
                    TextField("URL Pattern", text: $urlPattern, prompt: Text("/api/users"))
                        .font(.system(.body, design: .monospaced))
                }

                Section("Response Body") {
                    TextEditor(text: $responseBody)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 200)
                        .onChange(of: responseBody) {
                            validateJSON()
                        }

                    if let jsonError {
                        Label(jsonError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button("Format JSON") { formatJSON() }
                        .disabled(jsonError != nil)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            if let path = existingPath {
                urlPattern = path
                responseBody = mockManager.mocks[path] ?? "{}"
            }
        }
    }

    private func saveMock() {
        let path = urlPattern.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }

        // If editing and path changed, remove old one
        if let old = existingPath, old != path {
            mockManager.remove(path: old)
        }

        mockManager.save(path: path, response: responseBody)
        dismiss()
    }

    private func validateJSON() {
        guard let data = responseBody.data(using: .utf8) else {
            jsonError = "Invalid encoding"
            return
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data)
            jsonError = nil
        } catch {
            jsonError = "Not valid JSON (will be sent as plain text)"
        }
    }

    private func formatJSON() {
        guard let data = responseBody.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return }
        responseBody = str
    }
}

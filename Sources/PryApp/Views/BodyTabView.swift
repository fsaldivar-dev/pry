import SwiftUI
import PryLib

@available(macOS 14, *)
struct BodyTabView: View {
    let request: RequestStore.CapturedRequest

    private let maxBodySize = 100_000

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BodySection(title: "Request Body", content: request.requestBody, maxSize: maxBodySize)

                if request.statusCode != nil {
                    BodySection(title: "Response Body", content: request.responseBody, maxSize: maxBodySize)
                } else {
                    Text("Waiting for response...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@available(macOS 14, *)
private struct BodySection: View {
    let title: String
    let content: String?
    let maxSize: Int

    @State private var formattedText: String = ""
    @State private var isTruncated: Bool = false
    @State private var isJSON: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 4)

            if content != nil, !formattedText.isEmpty {
                if isJSON {
                    JSONSyntaxView(json: formattedText, alreadyFormatted: true)
                        .frame(maxHeight: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text(formattedText)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if isTruncated {
                    Text("Body truncated, showing first \(maxSize / 1000)KB")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            } else if content == nil || content!.isEmpty {
                Text("No body")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: content) {
            guard let text = content, !text.isEmpty else {
                formattedText = ""
                isTruncated = false
                return
            }
            isTruncated = text.count > maxSize
            let truncated = String(text.prefix(maxSize))
            // Check if JSON, then format off Main Thread
            let result = await Task.detached {
                (Self.formatBody(truncated), Self.checkJSON(truncated))
            }.value
            formattedText = result.0
            isJSON = result.1
        }
    }

    private nonisolated static func checkJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    /// Pretty-print JSON if valid, otherwise return as-is.
    private nonisolated static func formatBody(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return text }
        return str
    }
}

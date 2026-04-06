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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 4)

            if let bodyText = content, !bodyText.isEmpty {
                let displayed = bodyText.count > maxSize
                    ? String(bodyText.prefix(maxSize))
                    : bodyText

                Text(Self.formatBody(displayed))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                if bodyText.count > maxSize {
                    Text("Body truncated, showing first \(maxSize / 1000)KB")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            } else {
                Text("No body")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Pretty-print JSON if valid, otherwise return as-is.
    private static func formatBody(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return text }
        return str
    }
}

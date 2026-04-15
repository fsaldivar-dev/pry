import SwiftUI
import PryLib

@available(macOS 14, *)
struct HeadersTabView: View {
    let request: RequestStore.CapturedRequest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HeaderSection(title: "Request Headers", headers: request.requestHeaders)

                if request.statusCode != nil {
                    HeaderSection(title: "Response Headers", headers: request.responseHeaders)
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
private struct HeaderSection: View {
    let title: String
    let headers: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 4)

            if headers.isEmpty {
                Text("No headers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        GridRow {
                            Text(header.0)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(PryTheme.accent)
                                .textSelection(.enabled)
                            Text(header.1)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                    }
                }
            }
        }
    }
}

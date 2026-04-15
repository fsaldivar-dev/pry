import SwiftUI
import PryLib

@available(macOS 14, *)
struct RawTabView: View {
    let request: RequestStore.CapturedRequest

    private var rawRequest: String {
        var lines: [String] = []
        lines.append("\(request.method) \(request.url) HTTP/1.1")
        lines.append("Host: \(request.host)")
        for (name, value) in request.requestHeaders {
            lines.append("\(name): \(value)")
        }
        lines.append("")
        if let body = request.requestBody {
            lines.append(body)
        }
        return lines.joined(separator: "\r\n")
    }

    private var rawResponse: String? {
        guard let status = request.statusCode else { return nil }
        var lines: [String] = []
        lines.append("HTTP/1.1 \(status)")
        for (name, value) in request.responseHeaders {
            lines.append("\(name): \(value)")
        }
        lines.append("")
        if let body = request.responseBody {
            lines.append(body)
        }
        return lines.joined(separator: "\r\n")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Request")
                        .font(.headline)
                    Text(rawRequest)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(PryTheme.bgPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Response")
                        .font(.headline)
                    if let raw = rawResponse {
                        Text(raw)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(PryTheme.bgPanel)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Text("Waiting for response...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

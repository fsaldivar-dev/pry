import SwiftUI
import PryLib

@available(macOS 14, *)
struct CookiesTabView: View {
    let request: RequestStore.CapturedRequest

    private var cookies: [(name: String, value: String)] {
        let cookieHeaders = request.requestHeaders.filter { $0.0.lowercased() == "cookie" }
        return cookieHeaders.flatMap { parseCookies($0.1) }
    }

    private var setCookies: [(name: String, value: String)] {
        let headers = request.responseHeaders.filter { $0.0.lowercased() == "set-cookie" }
        return headers.flatMap { parseCookies($0.1) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CookieSection(title: "Request Cookies", cookies: cookies)
                if request.statusCode != nil {
                    CookieSection(title: "Response Set-Cookie", cookies: setCookies)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func parseCookies(_ header: String) -> [(name: String, value: String)] {
        header.split(separator: ";").compactMap { pair in
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            guard let eqIdx = trimmed.firstIndex(of: "=") else { return nil }
            let name = String(trimmed[trimmed.startIndex..<eqIdx])
            let value = String(trimmed[trimmed.index(after: eqIdx)...])
            return (name: name, value: value)
        }
    }
}

@available(macOS 14, *)
private struct CookieSection: View {
    let title: String
    let cookies: [(name: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 4)

            if cookies.isEmpty {
                Text("No cookies")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(Array(cookies.enumerated()), id: \.offset) { _, cookie in
                        GridRow {
                            Text(cookie.name)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.accentColor)
                                .textSelection(.enabled)
                            Text(cookie.value)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}

import SwiftUI

@available(macOS 14, *)
struct PausedRequestBanner: View {
    let method: String
    let url: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)
            Text("\(method) \(url)")
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
            Spacer()
            Text("Paused at breakpoint")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
    }
}

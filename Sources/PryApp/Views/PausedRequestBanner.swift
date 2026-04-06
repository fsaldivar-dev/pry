import SwiftUI

@available(macOS 14, *)
struct PausedRequestBanner: View {
    let method: String
    let url: String

    var body: some View {
        HStack {
            Image(systemName: "pause.circle.fill")
            Text("REQUEST PAUSED")
                .fontWeight(.bold)
            Text("— \(method) \(url)")
                .lineLimit(1)
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red)
    }
}

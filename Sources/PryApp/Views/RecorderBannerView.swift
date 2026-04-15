import SwiftUI
import PryKit

@available(macOS 14, *)
@MainActor
struct RecorderBannerView: View {
    @Environment(RecorderUIManager.self) private var recorder
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .opacity(isPulsing ? 0.3 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                .onAppear { isPulsing = true }

            Text("REC")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.red)

            Text("Recording traffic...")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Stop") {
                recorder.stop()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.1))
    }
}

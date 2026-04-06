import SwiftUI
import PryKit

@available(macOS 14, *)
struct StatusBarView: View {
    @Environment(ProxyManager.self) private var proxy
    @Environment(RequestStoreWrapper.self) private var store
    @Environment(MockManager.self) private var mocks

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Circle()
                    .fill(proxy.isRunning ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(proxy.isRunning ? "Running" : "Stopped")
                    .font(.caption)
            }

            Divider().frame(height: 12)

            Label(":\(proxy.port)", systemImage: "network")
                .font(.caption)

            Label("\(proxy.domains.count) domains", systemImage: "globe")
                .font(.caption)

            if mocks.mocks.count > 0 {
                Label("\(mocks.mocks.count) mocks", systemImage: "theatermask.and.paintbrush")
                    .font(.caption)
            }

            Spacer()

            Label("\(store.requests.count) requests", systemImage: "arrow.left.arrow.right")
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }
}

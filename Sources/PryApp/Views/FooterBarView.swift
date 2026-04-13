import SwiftUI
import PryKit

@available(macOS 14, *)
struct FooterBarView: View {
    @Environment(ProxyManager.self) private var proxy
    @Environment(RequestStoreWrapper.self) private var store
    @Environment(MockManager.self) private var mocks

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 20) {
                // Proxy status
                HStack(spacing: 6) {
                    Circle()
                        .fill(proxy.isRunning ? PryTheme.success : PryTheme.error)
                        .frame(width: 6, height: 6)
                        .shadow(color: proxy.isRunning ? PryTheme.success.opacity(0.5) : Color.clear, radius: 4)
                    Text("PROXY LOCAL: 127.0.0.1:\(String(proxy.port))")
                        .tracking(1.5)
                }

                // SSL status
                if proxy.domains.count > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "wifi")
                            .foregroundStyle(PryTheme.accent)
                            .font(.system(size: 10))
                        Text("CERTIFICADO SSL OK")
                            .tracking(1.5)
                    }
                }

                // Mocks
                if mocks.mocks.count > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "theatermask.and.paintbrush")
                            .font(.system(size: 10))
                        Text("\(mocks.mocks.count) MOCKS")
                            .tracking(1.5)
                    }
                }
            }

            Spacer()

            // Request count
            HStack(spacing: 4) {
                Text("\(store.filteredRequests.count) PETICIONES")
                    .tracking(1.5)
                    .foregroundStyle(PryTheme.accent)
            }
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(PryTheme.textTertiary)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
        }
    }
}

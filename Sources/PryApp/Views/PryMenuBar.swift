import SwiftUI
import PryKit

@available(macOS 14, *)
struct PryMenuBarContent: View {
    @Environment(ProxyManager.self) private var proxy
    @Environment(RequestStoreWrapper.self) private var store
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(proxy.isRunning ? PryTheme.success : PryTheme.error)
                    .frame(width: 8, height: 8)
                Text(proxy.isRunning ? "Proxy Running" : "Proxy Stopped")
                    .font(.headline)
            }
            .padding(.bottom, 4)

            Button(proxy.isRunning ? "Stop Proxy" : "Start Proxy") {
                if proxy.isRunning {
                    proxy.stop()
                } else {
                    do {
                        try proxy.start()
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Divider()

            Text("\(store.requests.count) requests captured")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("Show Window") {
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Quit Pry") {
                NSApp.terminate(nil)
            }
        }
        .padding()
        .frame(width: 200)
    }
}

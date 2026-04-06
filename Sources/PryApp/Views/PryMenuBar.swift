import SwiftUI
import PryKit

@available(macOS 14, *)
struct PryMenuBarContent: View {
    @Environment(ProxyManager.self) private var proxy
    @Environment(RequestStoreWrapper.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(proxy.isRunning ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(proxy.isRunning ? "Proxy Running" : "Proxy Stopped")
                    .font(.headline)
            }
            .padding(.bottom, 4)

            Button(proxy.isRunning ? "Stop Proxy" : "Start Proxy") {
                if proxy.isRunning {
                    proxy.stop()
                } else {
                    try? proxy.start()
                }
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

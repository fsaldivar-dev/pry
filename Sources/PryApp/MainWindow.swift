import SwiftUI
import PryKit
import PryLib

@available(macOS 14, *)
@MainActor
struct MainWindow: View {
    @Environment(ProxyManager.self) private var proxy
    @Environment(RequestStoreWrapper.self) private var store
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showMocks = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SourceListView()
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            } content: {
                VStack(spacing: 0) {
                    FilterBarView()
                    RequestListView()
                }
                .navigationSplitViewColumnWidth(min: 300, ideal: 450)
            } detail: {
                RequestDetailView()
            }
            .navigationTitle("Pry")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        toggleProxy()
                    } label: {
                        Image(systemName: proxy.isRunning ? "stop.fill" : "play.fill")
                        Text(proxy.isRunning ? "Stop" : "Start")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showMocks.toggle()
                    } label: {
                        Image(systemName: "theatermask.and.paintbrush")
                        Text("Mocks")
                    }
                }
            }
            .sheet(isPresented: $showMocks) {
                MockListView()
                    .frame(minWidth: 500, minHeight: 400)
            }

            StatusBarView()
        }
    }

    private func toggleProxy() {
        if proxy.isRunning {
            proxy.stop()
        } else {
            do {
                try proxy.start()
            } catch {
                print("Failed to start proxy: \(error)")
            }
        }
    }
}

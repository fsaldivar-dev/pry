import SwiftUI
import PryKit
import PryLib

@available(macOS 14, *)
@MainActor
struct MainWindow: View {
    @Environment(ProxyManager.self) private var proxy
    @Environment(RequestStoreWrapper.self) private var store
    @Environment(BreakpointUIManager.self) private var breakpoints
    @State private var showMocks = false
    @State private var showBreakpoints = false
    @State private var showRules = false

    var body: some View {
        VStack(spacing: 0) {
            // Paused request banner
            if let paused = breakpoints.pausedRequests.first {
                PausedRequestBanner(method: paused.method, url: paused.url)
            }

            HSplitView {
                // Left sidebar: source filter
                SourceListView()
                    .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)

                // Right: request list on top, detail panel on bottom
                VSplitView {
                    VStack(spacing: 0) {
                        FilterBarView()
                        RequestListView()
                    }
                    .frame(minHeight: 180)

                    DetailPanelView()
                        .frame(minHeight: 120, idealHeight: 280)
                }
            }

            StatusBarView()
        }
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
                    store.clear()
                } label: {
                    Image(systemName: "trash")
                    Text("Clear")
                }
                .help("Clear all captured requests")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showMocks.toggle()
                } label: {
                    Image(systemName: "theatermask.and.paintbrush")
                    Text("Mocks")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showBreakpoints.toggle()
                } label: {
                    Image(systemName: "pause.circle")
                    Text("Breakpoints")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showRules.toggle()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                    Text("Rules")
                }
            }
        }
        .sheet(isPresented: $showMocks) {
            MockListView()
                .frame(minWidth: 500, minHeight: 400)
        }
        .sheet(isPresented: $showBreakpoints) {
            BreakpointListView()
                .frame(minWidth: 500, minHeight: 400)
        }
        .sheet(isPresented: $showRules) {
            RulesEditorView()
                .frame(minWidth: 600, minHeight: 500)
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

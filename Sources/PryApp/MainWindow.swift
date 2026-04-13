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
        ZStack {
            // Gradient orbs background
            BackgroundView()

            VStack(spacing: 0) {
                // Paused request banner
                if let paused = breakpoints.pausedRequests.first {
                    PausedRequestBanner(method: paused.method, url: paused.url)
                }

                // Custom header bar (replaces native toolbar)
                HeaderBarView(
                    showMocks: $showMocks,
                    showBreakpoints: $showBreakpoints,
                    showRules: $showRules
                )

                if store.requests.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: proxy.isRunning
                            ? "antenna.radiowaves.left.and.right"
                            : "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(PryTheme.accent.opacity(0.6))
                        Text(proxy.isRunning ? "Waiting for traffic…" : "Proxy Stopped")
                            .font(.title2)
                            .foregroundStyle(PryTheme.textSecondary)
                        Text(proxy.isRunning
                            ? "Send requests through port \(String(proxy.port))"
                            : "Press **Start** to begin capturing")
                            .font(.callout)
                            .foregroundStyle(PryTheme.textTertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Main content: sidebar + glass panels
                    HStack(spacing: 0) {
                        SidebarView()
                            .frame(width: 260)

                        VStack(spacing: 10) {
                            // Request table in glass container
                            GlassContainer(style: .light) {
                                VStack(spacing: 0) {
                                    FilterBarView()
                                    RequestListView()
                                }
                            }

                            // Detail panel in dark glass container
                            GlassContainer(style: .dark) {
                                DetailPanelView()
                            }
                            .frame(minHeight: 200, idealHeight: 280)
                        }
                        .padding(10)
                    }
                }

                FooterBarView()
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
}

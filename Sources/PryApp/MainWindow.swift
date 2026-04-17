import SwiftUI
import PryKit
import PryLib

@available(macOS 14, *)
@MainActor
struct MainWindow: View {
    @Environment(ProxyManager.self) private var proxy
    @Environment(RequestStoreWrapper.self) private var store
    @Environment(BreakpointUIManager.self) private var breakpoints
    @Environment(RecorderUIManager.self) private var recorderManager
    @Environment(AppCore.self) private var core
    @State private var showMocking = false
    @State private var showBreakpoints = false
    @State private var showRules = false
    @State private var showDeviceSetup = false
    @State private var showBlocking = false
    @State private var showOverrides = false
    @State private var sidebarWidth: CGFloat = 220
    @State private var detailHeight: CGFloat = 280
    @State private var showSidebar = true

    var body: some View {
        VStack(spacing: 0) {
            if let paused = breakpoints.pausedRequests.first {
                PausedRequestBanner(method: paused.method, url: paused.url)
            }

            if recorderManager.isRecording {
                RecorderBannerView()
            }

            if let message = proxy.statusBanner {
                StatusBannerView(message: message) {
                    proxy.dismissStatusBanner()
                }
            }

            if store.requests.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: proxy.isRunning
                        ? "antenna.radiowaves.left.and.right"
                        : "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(PryTheme.accent.opacity(0.6))
                    Text(proxy.isRunning ? "Waiting for traffic..." : "Proxy Stopped")
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
                HStack(spacing: 0) {
                    // Collapsible sidebar
                    if showSidebar {
                        SidebarView()
                            .frame(width: sidebarWidth)
                            .transition(.move(edge: .leading).combined(with: .opacity))

                        DragDivider(axis: .vertical) { delta in
                            sidebarWidth = max(140, min(300, sidebarWidth + delta))
                        }
                    }

                    // Right content
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            FilterBarView()
                            RequestListView()
                        }

                        DragDivider(axis: .horizontal) { delta in
                            detailHeight = max(80, detailHeight - delta)
                        }

                        DetailPanelView()
                            .frame(height: detailHeight)
                    }
                }
            }

            FooterBarView()
        }
        .background(PryTheme.bgMain)
        .toolbarBackground(.hidden)
        .toolbar {
            // Sidebar toggle
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showSidebar.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar (⌘0)")
                .keyboardShortcut("0", modifiers: .command)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { toggleProxy() } label: {
                    Image(systemName: proxy.isRunning ? "stop.fill" : "play.fill")
                    Text(proxy.isRunning ? "Stop" : "Start")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button { store.clear() } label: {
                    Image(systemName: "trash")
                    Text("Clear")
                }
                .help("Clear all captured requests")
            }
            ToolbarItem(placement: .automatic) {
                Button { showMocking.toggle() } label: {
                    Image(systemName: "theatermask.and.paintbrush")
                    Text("Mocking")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button { showBreakpoints.toggle() } label: {
                    Image(systemName: "pause.circle")
                    Text("Breakpoints")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button { showRules.toggle() } label: {
                    Image(systemName: "list.bullet.rectangle")
                    Text("Rules")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button { showDeviceSetup.toggle() } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Device")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button { showBlocking.toggle() } label: {
                    Image(systemName: "shield.fill")
                    Text("Blocking")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button { showOverrides.toggle() } label: {
                    Image(systemName: "arrow.up.right.diamond.fill")
                    Text("Overrides")
                }
            }
        }
        .sheet(isPresented: $showMocking) {
            UnifiedMockView().frame(minWidth: 800, minHeight: 500)
        }
        .sheet(isPresented: $showBlocking) {
            BlocksView().frame(minWidth: 500, minHeight: 400)
        }
        .sheet(isPresented: $showOverrides) {
            StatusOverridesView().frame(minWidth: 500, minHeight: 400)
        }
        .sheet(isPresented: $showBreakpoints) {
            BreakpointListView().frame(minWidth: 500, minHeight: 400)
        }
        .sheet(isPresented: $showRules) {
            RulesEditorView().frame(minWidth: 600, minHeight: 500)
        }
        .sheet(isPresented: $showDeviceSetup) {
            DeviceSetupView().frame(minWidth: 450, minHeight: 400)
        }
    }

    private func toggleProxy() {
        if proxy.isRunning {
            proxy.stop()
        } else {
            // Pasamos core.interceptors para que la chain nueva (ADR-006) corra en el
            // pipeline real — BlockInterceptor y futuros interceptors ejecutan de verdad.
            do { try proxy.start(interceptors: core.interceptors) } catch { print("Failed to start proxy: \(error)") }
        }
    }
}

// MARK: - Drag divider for resizable panels

@available(macOS 14, *)
struct DragDivider: View {
    enum Axis { case vertical, horizontal }
    let axis: Axis
    let onDrag: (CGFloat) -> Void

    var body: some View {
        Group {
            if axis == .vertical {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
                    .contentShape(Rectangle().size(width: 8, height: .infinity))
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() }
                        else { NSCursor.pop() }
                    }
                    .gesture(DragGesture()
                        .onChanged { value in onDrag(value.translation.width) }
                    )
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .contentShape(Rectangle().size(width: .infinity, height: 8))
                    .onHover { inside in
                        if inside { NSCursor.resizeUpDown.push() }
                        else { NSCursor.pop() }
                    }
                    .gesture(DragGesture()
                        .onChanged { value in onDrag(value.translation.height) }
                    )
            }
        }
    }
}

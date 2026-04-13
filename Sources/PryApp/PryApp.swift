import SwiftUI
import PryKit

@available(macOS 14, *)
@MainActor
@main
struct PryApp: App {
    @State private var proxyManager = ProxyManager()
    @State private var requestStore = RequestStoreWrapper()
    @State private var mockManager = MockManager()
    @State private var breakpointManager = BreakpointUIManager()

    init() {
        // Ensure the app activates as a regular foreground app even when
        // launched from the command line (e.g. `PryApp &`).
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(proxyManager)
                .environment(requestStore)
                .environment(mockManager)
                .environment(breakpointManager)
        }
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView()
                .environment(proxyManager)
        }

        MenuBarExtra("Pry", systemImage: "cat.fill") {
            PryMenuBarContent()
                .environment(proxyManager)
                .environment(requestStore)
        }
        .menuBarExtraStyle(.window)
    }
}

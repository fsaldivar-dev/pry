import SwiftUI
import PryKit

@available(macOS 14, *)
@main
struct PryApp: App {
    @State private var proxyManager = ProxyManager()
    @State private var requestStore = RequestStoreWrapper()
    @State private var mockManager = MockManager()
    @State private var breakpointManager = BreakpointUIManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(proxyManager)
                .environment(requestStore)
                .environment(mockManager)
                .environment(breakpointManager)
        }
        .defaultSize(width: 1200, height: 800)

        MenuBarExtra("Pry", systemImage: "cat.fill") {
            PryMenuBarContent()
                .environment(proxyManager)
                .environment(requestStore)
        }
        .menuBarExtraStyle(.window)
    }
}

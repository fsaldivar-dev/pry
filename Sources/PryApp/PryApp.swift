import SwiftUI
import AppKit
import PryKit
import PryLib

@available(macOS 14, *)
@MainActor
@main
struct PryApp: App {
    @NSApplicationDelegateAdaptor(PryAppDelegate.self) var delegate
    @State private var proxyManager = ProxyManager()
    @State private var requestStore = RequestStoreWrapper()
    @State private var mockManager = MockManager()
    @State private var breakpointManager = BreakpointUIManager()
    @State private var recorderManager = RecorderUIManager()
    @State private var projectUIManager = ProjectUIManager()
    /// Composition root de la arquitectura nueva (ADR-006). Convive con los
    /// managers legacy durante la migración — cada feature migra uno por uno
    /// y los managers legacy se retiran cuando se queden sin consumers.
    @State private var core = AppCore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(proxyManager)
                .environment(requestStore)
                .environment(mockManager)
                .environment(breakpointManager)
                .environment(recorderManager)
                .environment(projectUIManager)
                .environment(core)
        }
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView()
                .environment(proxyManager)
        }

        MenuBarExtra("Pry", systemImage: "cat") {
            PryMenuBarContent()
                .environment(proxyManager)
                .environment(requestStore)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - AppDelegate for window-level configuration

@available(macOS 14, *)
final class PryAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Clean up orphaned proxy config from a previous crash
        ProxyGuard.cleanupIfNeeded()
        // Force dark appearance and custom background on ALL windows
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        applyWindowBackground()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        applyWindowBackground()
    }

    private func applyWindowBackground() {
        let bgColor = NSColor(red: 13/255, green: 17/255, blue: 23/255, alpha: 1) // #0D1117
        for window in NSApplication.shared.windows {
            window.backgroundColor = bgColor
            window.appearance = NSAppearance(named: .darkAqua)
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
        }
    }
}

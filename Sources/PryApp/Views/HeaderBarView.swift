import SwiftUI
import PryKit

// MARK: - HeaderBarView

/// Custom header bar that replaces the native macOS toolbar.
/// Provides proxy controls, quick-access tool buttons, and app branding.
@available(macOS 14, *)
@MainActor
struct HeaderBarView: View {
    @Environment(ProxyManager.self) private var proxy
    @Environment(RequestStoreWrapper.self) private var store

    @Binding var showMocks: Bool
    @Binding var showBreakpoints: Bool
    @Binding var showRules: Bool

    var body: some View {
        HStack(spacing: 0) {
            // --- Left section: branding ---
            brandingSection
                .padding(.leading, 16)

            Spacer(minLength: 12)

            // --- Right section: toolbar buttons ---
            toolbarSection
                .padding(.trailing, 16)
        }
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.40))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
        }
    }

    // MARK: - Branding

    private var brandingSection: some View {
        HStack(spacing: 10) {
            // App icon: cat in gradient rounded square
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [PryTheme.accent, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)

                Image(systemName: "cat.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("PryApp")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            // INSIGHT badge
            Text("INSIGHT")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(PryTheme.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                )
        }
    }

    // MARK: - Toolbar Buttons

    private var toolbarSection: some View {
        HStack(spacing: 6) {
            // Start / Stop proxy
            proxyToggleButton

            headerDivider

            // Clear captured requests
            headerButton(
                icon: "trash",
                label: "Clear",
                action: { store.clear() }
            )

            headerDivider

            // Tool buttons
            headerButton(
                icon: "theatermask.and.paintbrush",
                label: "Mocks",
                isActive: showMocks,
                action: { showMocks.toggle() }
            )
            headerButton(
                icon: "pause.circle",
                label: "Breakpoints",
                isActive: showBreakpoints,
                action: { showBreakpoints.toggle() }
            )
            headerButton(
                icon: "list.bullet.rectangle",
                label: "Rules",
                isActive: showRules,
                action: { showRules.toggle() }
            )

            headerDivider

            // Settings
            headerButton(
                icon: "gear",
                label: "Settings",
                action: { openSettings() }
            )
        }
    }

    // MARK: - Proxy Toggle

    private var proxyToggleButton: some View {
        Button(action: toggleProxy) {
            HStack(spacing: 6) {
                // Pulsing status dot when running
                if proxy.isRunning {
                    Circle()
                        .fill(PryTheme.success)
                        .frame(width: 7, height: 7)
                        .shadow(color: PryTheme.success.opacity(0.6), radius: 4)
                        .modifier(PulseModifier())
                }

                Image(systemName: proxy.isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))

                Text(proxy.isRunning ? "Stop" : "Start")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(proxy.isRunning ? PryTheme.error : PryTheme.success)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        proxy.isRunning
                            ? PryTheme.error.opacity(0.12)
                            : PryTheme.success.opacity(0.12)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        proxy.isRunning
                            ? PryTheme.error.opacity(0.3)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Generic Header Button

    private func headerButton(
        icon: String,
        label: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(
                isActive ? PryTheme.accent : PryTheme.textSecondary
            )
            .frame(width: 52, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isActive
                            ? PryTheme.accent.opacity(0.1)
                            : Color.white.opacity(0.001) // hit-target
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Visual Helpers

    private var headerDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 4)
    }

    // MARK: - Actions

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

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

// MARK: - Pulse Animation Modifier

/// Subtle pulsing animation for the active proxy status dot.
private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

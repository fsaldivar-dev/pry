import SwiftUI
import PryKit
import PryLib

/// Alias to disambiguate SwiftUI.Color from PryLib.Color (ANSI).
private typealias SColor = SwiftUI.Color

// MARK: - Icon descriptor for app cards

private struct AppIcon {
    let symbol: String
    let color: SColor
}

// MARK: - SidebarView

@available(macOS 14, *)
@MainActor
struct SidebarView: View {
    @Environment(RequestStoreWrapper.self) private var store
    @State private var grouped: [AppGroup] = []
    @State private var hoveredCard: String?

    var body: some View {
        @Bindable var store = store

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {

                // MARK: Header
                sectionHeader

                // MARK: All Traffic card
                allTrafficCard

                // MARK: App group cards
                if !grouped.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(grouped) { group in
                            appCard(for: group)
                        }
                    }
                }

                Spacer(minLength: 24)

                // MARK: Security card
                securityCard
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .background(PryTheme.bgMain)
        .onChange(of: store.requests.count) {
            recomputeGroups()
        }
        .onAppear {
            recomputeGroups()
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        Text("APLICACIONES ACTIVAS")
            .font(.system(size: 10, weight: .bold))
            .tracking(2)
            .textCase(.uppercase)
            .foregroundStyle(PryTheme.textTertiary)
            .padding(.leading, 4)
            .padding(.bottom, 2)
    }

    // MARK: - All Traffic Card

    private var allTrafficCard: some View {
        let isSelected = store.selectedSource == .all || store.selectedSource == nil
        let isHovered = hoveredCard == "__all__"

        return Button {
            store.selectedSource = .all
        } label: {
            HStack(spacing: 12) {
                // Icon container
                iconContainer(
                    symbol: "arrow.left.arrow.right",
                    color: PryTheme.accent,
                    isSelected: isSelected
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Todo el Trafico")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PryTheme.textPrimary)

                    Text("\(store.requests.count) peticiones")
                        .font(.caption)
                        .foregroundStyle(PryTheme.textSecondary)
                }

                Spacer()

                // Badge
                requestBadge(count: store.requests.count)

                // Active dot
                if isSelected {
                    activeDot
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(cardBackground(isSelected: isSelected, isHovered: isHovered))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? SColor.white.opacity(0.1) : SColor.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredCard = hovering ? "__all__" : nil
        }
    }

    // MARK: - App Card

    private func appCard(for group: AppGroup) -> some View {
        let sourceTag = SourceFilter.app(group.id)
        let isSelected = store.selectedSource == sourceTag
        let isHovered = hoveredCard == group.id
        let icon = iconForApp(group.id)
        let displayName = group.id.isEmpty ? "Unknown" : (group.id == "tunnel" ? "Passthrough (tunnel)" : group.id)

        return Button {
            store.selectedSource = sourceTag
        } label: {
            HStack(spacing: 12) {
                // Icon container
                iconContainer(
                    symbol: icon.symbol,
                    color: icon.color,
                    isSelected: isSelected
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            group.id == "tunnel"
                                ? PryTheme.textSecondary
                                : PryTheme.textPrimary
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("\(group.total) peticiones")
                        .font(.caption)
                        .foregroundStyle(PryTheme.textSecondary)
                }

                Spacer()

                // Badge
                requestBadge(count: group.total)

                // Active dot
                if isSelected {
                    activeDot
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(cardBackground(isSelected: isSelected, isHovered: isHovered))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? SColor.white.opacity(0.1) : SColor.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredCard = hovering ? group.id : nil
        }
    }

    // MARK: - Security Card

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SColor.indigo, SColor.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("SEGURIDAD")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(PryTheme.textTertiary)
            }

            Text("Trafico HTTPS interceptado con certificado local activo.")
                .font(.system(size: 11))
                .foregroundStyle(PryTheme.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    SColor.indigo.opacity(0.10),
                    SColor.purple.opacity(0.10)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(SColor.indigo.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Reusable Components

    /// Rounded icon container (36x36).
    private func iconContainer(symbol: String, color: SColor, isSelected: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? color : color.opacity(0.9))
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? SColor.white.opacity(0.12) : color.opacity(0.15))
            )
    }

    /// Small badge showing a request count.
    private func requestBadge(count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(PryTheme.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(SColor.white.opacity(0.06))
            )
    }

    /// Cyan active-selection dot with glow.
    private var activeDot: some View {
        Circle()
            .fill(PryTheme.accent)
            .frame(width: 6, height: 6)
            .shadow(color: PryTheme.accent.opacity(0.6), radius: 4, x: 0, y: 0)
    }

    /// Card background that responds to selection/hover.
    private func cardBackground(isSelected: Bool, isHovered: Bool) -> some ShapeStyle {
        if isSelected {
            return SColor.white.opacity(0.1)
        } else if isHovered {
            return SColor.white.opacity(0.05)
        } else {
            return SColor.white.opacity(0.0)
        }
    }

    // MARK: - Helpers

    private func recomputeGroups() {
        grouped = SourceListView.computeGrouped(store.requests)
    }

    /// Map an app name to an SF Symbol + tint color.
    private func iconForApp(_ appName: String) -> AppIcon {
        let name = appName.lowercased()
        if name.contains("simulator") || name.contains("pry") {
            return AppIcon(symbol: "bolt.fill", color: PryTheme.accent)
        }
        if name.contains("safari") {
            return AppIcon(symbol: "safari.fill", color: SColor.blue)
        }
        if name.contains("chrome") {
            return AppIcon(symbol: "globe", color: PryTheme.warning)
        }
        if name.contains("whatsapp") {
            return AppIcon(symbol: "phone.fill", color: PryTheme.success)
        }
        if name.contains("apple") || name.contains("cloudkit") {
            return AppIcon(symbol: "shield.fill", color: SColor.blue)
        }
        if name == "tunnel" {
            return AppIcon(symbol: "lock.fill", color: PryTheme.textTertiary)
        }
        return AppIcon(symbol: "app.fill", color: SColor.white)
    }
}

import SwiftUI

@available(macOS 14, *)
struct UnderlineTabBar: View {
    @Binding var selectedTab: DetailPanelView.Tab
    let visibleTabs: [DetailPanelView.Tab]
    var onCopyCurl: (() -> Void)? = nil
    @Namespace private var tabNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 0) {
                        Text(tab.rawValue.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(selectedTab == tab ? PryTheme.textPrimary : PryTheme.textTertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

                        // Underline indicator
                        if selectedTab == tab {
                            Rectangle()
                                .fill(PryTheme.accent)
                                .frame(height: 2)
                                .shadow(color: PryTheme.accent.opacity(0.6), radius: 6, y: 2)
                                .matchedGeometryEffect(id: "tabUnderline", in: tabNamespace)
                        } else {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Copy cURL button
            if let onCopyCurl {
                Button {
                    onCopyCurl()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "terminal")
                            .font(.system(size: 10))
                        Text("COPIAR CURL")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1)
                    }
                    .foregroundStyle(PryTheme.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }
        }
        .background(Color.white.opacity(0.03))
    }
}

import SwiftUI

@available(macOS 14, *)
struct GlassContainer<Content: View>: View {
    enum Style { case light, dark }
    let style: Style
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content

    init(style: Style = .light, cornerRadius: CGFloat = 20, @ViewBuilder content: @escaping () -> Content) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(style == .dark
                        ? Color.black.opacity(0.40)
                        : Color.white.opacity(0.05))
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 20, y: 8)
    }
}

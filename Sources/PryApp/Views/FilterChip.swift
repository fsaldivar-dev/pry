import SwiftUI

@available(macOS 14, *)
struct FilterChip: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isActive ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

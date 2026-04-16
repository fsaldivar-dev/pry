import SwiftUI

/// Banner de estado efímero — muestra un mensaje informativo arriba del contenido
/// principal. Se usa para avisar cambios que pueden no ser obvios al usuario
/// (ej. "dominio agregado — reiniciá el cliente si no ves tráfico").
///
/// Se auto-dismissea tras 6 segundos, o manualmente con el botón X.
@available(macOS 14, *)
struct StatusBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.cyan)
            Text(message)
                .font(.callout)
                .foregroundStyle(PryTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(PryTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.cyan.opacity(0.12))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.cyan.opacity(0.3))
                .frame(height: 1)
        }
        .task {
            // Auto-dismiss a los 6s.
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            onDismiss()
        }
    }
}

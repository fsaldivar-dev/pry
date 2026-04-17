import SwiftUI

/// Envuelve el contenido de una sheet con un header que tiene botón Done
/// + atajo Esc para cerrar. Resuelve el problema de que las views de feature
/// (BlocksView, StatusOverridesView, etc.) no tienen dismiss built-in cuando
/// se presentan via `.sheet(isPresented:)`.
///
/// Uso:
/// ```
/// .sheet(isPresented: $showX) {
///     MyView().dismissibleSheet()
/// }
/// ```
@available(macOS 14, *)
private struct DismissibleSheet<Content: View>: View {
    let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction) // Esc
                    .keyboardShortcut(.defaultAction) // Enter
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            content
        }
    }
}

@available(macOS 14, *)
extension View {
    /// Agrega un botón "Done" en el header + Esc + Enter para cerrar la sheet.
    public func dismissibleSheet() -> some View {
        DismissibleSheet(content: self)
    }
}

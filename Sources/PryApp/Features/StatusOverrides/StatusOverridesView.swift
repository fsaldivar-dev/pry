import SwiftUI

/// UI para gestionar la lista de status overrides. Consume `StatusOverridesStore`
/// via `AppCore` inyectado en `@Environment`.
@available(macOS 14, *)
struct StatusOverridesView: View {
    @Environment(AppCore.self) private var core

    @State private var newPattern: String = ""
    @State private var newStatus: Int = 500

    /// Status codes de HTTP más comunes para testing de error UI.
    private static let commonStatuses: [Int] = [400, 401, 403, 404, 418, 500, 502, 503, 504]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header con input para agregar.
            HStack {
                TextField("URL pattern (ej. /api/login o */checkout*)", text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addCurrent() }
                Picker("Status", selection: $newStatus) {
                    ForEach(Self.commonStatuses, id: \.self) { code in
                        Text("\(code)").tag(code)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 90)
                Button("Add") { addCurrent() }
                    .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            Divider()

            // Lista de overrides.
            if core.statusOverrides.overrides.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.diamond")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No hay status overrides")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(core.statusOverrides.overrides, id: \.pattern) { override in
                        HStack {
                            Image(systemName: "arrow.up.right.diamond.fill")
                                .foregroundStyle(color(for: override.status))
                            Text(override.pattern)
                            Spacer()
                            Text("\(override.status)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(color(for: override.status))
                            Button {
                                core.statusOverrides.remove(pattern: override.pattern)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Status Overrides")
    }

    @MainActor
    private func addCurrent() {
        let trimmed = newPattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        core.statusOverrides.add(pattern: trimmed, status: newStatus)
        newPattern = ""
    }

    /// Color visual según familia de status: 4xx amarillo, 5xx rojo, resto neutro.
    private func color(for status: Int) -> Color {
        switch status {
        case 500...599: return .red.opacity(0.85)
        case 400...499: return .orange.opacity(0.85)
        default: return .secondary
        }
    }
}

// Previews usan el estilo viejo (PreviewProvider) porque el macro `#Preview` no
// soporta `@available` y el package apunta a macOS 13 para mantener compatibilidad
// con la CLI. Los PreviewProviders permiten gating por availability de forma limpia.
@available(macOS 14, *)
struct StatusOverridesView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            StatusOverridesView()
                .environment(AppCore.preview())
                .previewDisplayName("empty")

            StatusOverridesView()
                .environment(AppCore.previewWithStatusOverrides([
                    ("/api/login", 500),
                    ("*/checkout*", 503),
                    ("/api/search", 429)
                ]))
                .previewDisplayName("with data")
        }
        .frame(width: 500, height: 400)
    }
}

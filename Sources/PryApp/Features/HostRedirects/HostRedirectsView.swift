import SwiftUI

/// UI para gestionar la lista de host redirects. Consume `HostRedirectsStore`
/// via `AppCore` inyectado en `@Environment`.
@available(macOS 14, *)
struct HostRedirectsView: View {
    @Environment(AppCore.self) private var core

    @State private var newSource: String = ""
    @State private var newTarget: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header con input para agregar.
            HStack {
                TextField("Source host (ej. api.test.com)", text: $newSource)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addCurrent() }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                TextField("Target host (ej. api.stage.com)", text: $newTarget)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addCurrent() }
                Button("Add") { addCurrent() }
                    .disabled(!canAdd)
            }
            .padding()

            Divider()

            // Lista de redirects.
            if core.hostRedirects.redirects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No hay host redirects")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(core.hostRedirects.redirects, id: \.sourceHost) { redirect in
                        HStack {
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundStyle(Color.accentColor)
                            Text(redirect.sourceHost)
                                .font(.system(.body, design: .monospaced))
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            Text(redirect.targetHost)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button {
                                core.hostRedirects.remove(source: redirect.sourceHost)
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
        .navigationTitle("Host Redirects")
    }

    private var canAdd: Bool {
        !newSource.trimmingCharacters(in: .whitespaces).isEmpty &&
        !newTarget.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @MainActor
    private func addCurrent() {
        let src = newSource.trimmingCharacters(in: .whitespaces)
        let tgt = newTarget.trimmingCharacters(in: .whitespaces)
        guard !src.isEmpty, !tgt.isEmpty else { return }
        core.hostRedirects.add(source: src, target: tgt)
        newSource = ""
        newTarget = ""
    }
}

// Previews usan el estilo viejo (PreviewProvider) porque el macro `#Preview` no
// soporta `@available` y el package apunta a macOS 13 para mantener compatibilidad
// con la CLI. Los PreviewProviders permiten gating por availability de forma limpia.
@available(macOS 14, *)
struct HostRedirectsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            HostRedirectsView()
                .environment(AppCore.preview())
                .previewDisplayName("empty")

            HostRedirectsView()
                .environment(AppCore.previewWithHostRedirects([
                    ("api.test.com", "api.stage.com"),
                    ("cdn.test.com", "cdn.stage.com"),
                    ("auth.example.com", "auth.staging.example.com")
                ]))
                .previewDisplayName("with data")
        }
        .frame(width: 600, height: 400)
    }
}

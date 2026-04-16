import SwiftUI

/// UI para gestionar la lista de dominios bloqueados. Consume `BlockStore` via
/// `AppCore` inyectado en `@Environment`.
@available(macOS 14, *)
struct BlocksView: View {
    @Environment(AppCore.self) private var core

    @State private var newDomain: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header con input para agregar.
            HStack {
                TextField("domain.com o *.domain.com", text: $newDomain)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addCurrent() }
                Button("Add") { addCurrent() }
                    .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            Divider()

            // Lista de dominios.
            if core.blocks.domains.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shield.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No hay dominios bloqueados")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(core.blocks.domains, id: \.self) { domain in
                        HStack {
                            Image(systemName: "shield.fill")
                                .foregroundStyle(.red.opacity(0.8))
                            Text(domain)
                            Spacer()
                            Button {
                                core.blocks.remove(domain)
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
        .navigationTitle("Blocking")
    }

    @MainActor
    private func addCurrent() {
        let trimmed = newDomain.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        core.blocks.add(trimmed)
        newDomain = ""
    }
}

// Previews usan el estilo viejo (PreviewProvider) porque el macro `#Preview` no
// soporta `@available` y el package apunta a macOS 13 para mantener compatibilidad
// con la CLI. Los PreviewProviders permiten gating por availability de forma limpia.
@available(macOS 14, *)
struct BlocksView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            BlocksView()
                .environment(AppCore.preview())
                .previewDisplayName("empty")

            BlocksView()
                .environment(AppCore.previewWithBlockedDomains([
                    "ads.tracker.com",
                    "*.analytics.com"
                ]))
                .previewDisplayName("with data")
        }
        .frame(width: 400, height: 400)
    }
}

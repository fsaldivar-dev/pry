import SwiftUI
import PryLib

/// UI de Session Persistence: toggle opt-in + stats + clear.
@available(macOS 14, *)
struct SessionPersistenceView: View {
    @Environment(AppCore.self) private var core

    @State private var showConfirmClear = false

    var body: some View {
        @Bindable var store = core.sessionPersistence

        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $store.isEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Persist session across restarts")
                        .font(.headline)
                    Text("Guarda cada request/response capturado a disco. Opt-in por privacidad — disabled por default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Divider()

            // Stats
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("\(store.persistedCount) requests persistidos")
                } icon: {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.blue)
                }

                Label {
                    Text(humanSize(store.persistedBytes))
                } icon: {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(.secondary)
                }

                if store.persistedCount >= SessionPersistence.maxEntries {
                    Label {
                        Text("Cap de \(SessionPersistence.maxEntries) entradas alcanzado — se descartan las más viejas.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Divider()

            HStack {
                Button(role: .destructive) {
                    showConfirmClear = true
                } label: {
                    Label("Clear persisted session", systemImage: "trash")
                }
                .disabled(store.persistedCount == 0)

                Button("Refresh stats") {
                    store.refreshStats()
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            Spacer()

            // Note técnica
            Text("Archivo: `~/.pry/sessions/last.jsonl` (JSONL, append-only, prune automático al superar 5000 entries o 50 MB).")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding()
        .navigationTitle("Session Persistence")
        .confirmationDialog(
            "¿Borrar la sesión persistida?",
            isPresented: $showConfirmClear
        ) {
            Button("Borrar", role: .destructive) {
                store.clearPersisted()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se va a eliminar \(store.persistedCount) requests guardadas. Esta acción no es reversible.")
        }
        .onAppear {
            store.refreshStats()
        }
    }

    private func humanSize(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1 { return "\(bytes) B" }
        let mb = kb / 1024
        if mb < 1 { return String(format: "%.1f KB", kb) }
        return String(format: "%.2f MB", mb)
    }
}

@available(macOS 14, *)
struct SessionPersistenceView_Previews: PreviewProvider {
    static var previews: some View {
        SessionPersistenceView()
            .environment(AppCore.preview())
            .frame(width: 500, height: 400)
    }
}

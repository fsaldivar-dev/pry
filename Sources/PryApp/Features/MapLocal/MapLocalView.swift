import SwiftUI
import AppKit

/// UI para gestionar mappings de Map Local. Consume `MapLocalStore` via
/// `AppCore` inyectado en `@Environment`.
@available(macOS 14, *)
struct MapLocalView: View {
    @Environment(AppCore.self) private var core

    @State private var newPattern: String = ""
    @State private var newFilePath: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header con inputs para agregar.
            VStack(alignment: .leading, spacing: 8) {
                TextField("URL regex (ej. ^https://api\\.example\\.com/users$)", text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Path al archivo local", text: $newFilePath)
                        .textFieldStyle(.roundedBorder)
                    Button("Pick file…") { pickFile() }
                    Button("Add") { addCurrent() }
                        .disabled(!canAdd)
                }
            }
            .padding()

            Divider()

            // Lista de mappings.
            if core.mapLocal.mappings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No hay mappings de Map Local")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(core.mapLocal.mappings, id: \.pattern) { mapping in
                        HStack(alignment: .top) {
                            Image(systemName: "arrow.right.doc.on.clipboard")
                                .foregroundStyle(.blue.opacity(0.8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mapping.pattern)
                                    .font(.system(.body, design: .monospaced))
                                Text(mapping.filePath)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                core.mapLocal.remove(pattern: mapping.pattern)
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
        .navigationTitle("Map Local")
    }

    private var canAdd: Bool {
        !newPattern.trimmingCharacters(in: .whitespaces).isEmpty &&
        !newFilePath.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @MainActor
    private func addCurrent() {
        let pattern = newPattern.trimmingCharacters(in: .whitespaces)
        let path = newFilePath.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty, !path.isEmpty else { return }
        core.mapLocal.add(pattern: pattern, filePath: path)
        newPattern = ""
        newFilePath = ""
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            newFilePath = url.path
        }
    }
}

// Previews usan PreviewProvider (no el macro #Preview) porque el package
// target es macOS 13 y el macro no permite @available(macOS 14, *).
@available(macOS 14, *)
struct MapLocalView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MapLocalView()
                .environment(AppCore.preview())
                .previewDisplayName("empty")

            MapLocalView()
                .environment(AppCore.previewWithMapLocalMappings([
                    ("^https://api\\.example\\.com/users$", "/tmp/users.json"),
                    (".*\\.analytics\\.com.*", "/tmp/empty.json")
                ]))
                .previewDisplayName("with data")
        }
        .frame(width: 500, height: 400)
    }
}

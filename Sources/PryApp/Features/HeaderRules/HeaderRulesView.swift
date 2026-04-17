import SwiftUI

/// UI para gestionar reglas de rewrite de headers. Consume `HeaderRulesStore`
/// via `AppCore` inyectado en `@Environment`.
///
/// El usuario elige entre `Set` (agregar/reemplazar header con valor) y
/// `Remove` (eliminar header). El campo `value` se deshabilita cuando la acción
/// es `Remove` — no tiene sentido ahí.
@available(macOS 14, *)
struct HeaderRulesView: View {
    @Environment(AppCore.self) private var core

    @State private var selectedAction: HeaderRuleAction = .set
    @State private var newName: String = ""
    @State private var newValue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header con form para agregar.
            HStack {
                Picker("Action", selection: $selectedAction) {
                    Text("Set").tag(HeaderRuleAction.set)
                    Text("Remove").tag(HeaderRuleAction.remove)
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                TextField("Header name (ej. Authorization)", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addCurrent() }

                TextField("Value (ej. Bearer dev-token)", text: $newValue)
                    .textFieldStyle(.roundedBorder)
                    .disabled(selectedAction == .remove)
                    .onSubmit { addCurrent() }

                Button("Add") { addCurrent() }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            Divider()

            // Lista de reglas.
            if core.headerRules.rules.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No hay reglas de headers")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(core.headerRules.rules) { rule in
                        HStack {
                            Image(systemName: icon(for: rule.action))
                                .foregroundStyle(color(for: rule.action))
                            Text(label(for: rule.action))
                                .font(.caption)
                                .foregroundStyle(color(for: rule.action))
                                .frame(width: 60, alignment: .leading)
                            Text(rule.name)
                                .font(.system(.body, design: .monospaced))
                            if rule.action == .set {
                                Text("=")
                                    .foregroundStyle(.secondary)
                                Text(rule.value)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            Spacer()
                            Button {
                                core.headerRules.remove(rule: rule)
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
        .navigationTitle("Header Rules")
    }

    @MainActor
    private func addCurrent() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        switch selectedAction {
        case .set:
            core.headerRules.addSet(name: trimmed, value: newValue)
        case .remove:
            core.headerRules.addRemove(name: trimmed)
        }
        newName = ""
        newValue = ""
    }

    private func icon(for action: HeaderRuleAction) -> String {
        switch action {
        case .set:    return "plus.circle.fill"
        case .remove: return "minus.circle.fill"
        }
    }

    private func color(for action: HeaderRuleAction) -> Color {
        switch action {
        case .set:    return .green.opacity(0.85)
        case .remove: return .red.opacity(0.85)
        }
    }

    private func label(for action: HeaderRuleAction) -> String {
        switch action {
        case .set:    return "SET"
        case .remove: return "REMOVE"
        }
    }
}

// Previews: estilo PreviewProvider porque `#Preview` no soporta `@available` y
// el package apunta a macOS 13 para mantener compatibilidad con la CLI.
@available(macOS 14, *)
struct HeaderRulesView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            HeaderRulesView()
                .environment(AppCore.preview())
                .previewDisplayName("empty")

            HeaderRulesView()
                .environment(AppCore.previewWithHeaderRules([
                    (.set, "Authorization", "Bearer dev-token"),
                    (.set, "X-Debug", "true"),
                    (.remove, "Cookie", "")
                ]))
                .previewDisplayName("with data")
        }
        .frame(width: 600, height: 400)
    }
}

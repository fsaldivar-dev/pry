import SwiftUI

/// UI para gestionar patterns de breakpoints. Consume `BreakpointStore` via
/// `AppCore` inyectado en `@Environment`.
@available(macOS 14, *)
@MainActor
struct BreakpointsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCore.self) private var core
    @State private var newPattern: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Breakpoints")
                    .font(.headline)
                Spacer()
                if !core.breakpoints.patterns.isEmpty {
                    Button { core.breakpoints.clearAll() } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear All")
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            HStack {
                TextField("URL pattern (e.g. */api/*)", text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit { addPattern() }
                Button("Add") { addPattern() }
                    .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if core.breakpoints.patterns.isEmpty {
                ContentUnavailableView(
                    "No Breakpoints",
                    systemImage: "pause.circle",
                    description: Text("Add a URL pattern to pause matching requests")
                )
            } else {
                List {
                    ForEach(core.breakpoints.patterns, id: \.self) { pattern in
                        HStack {
                            Image(systemName: "pause.circle")
                                .foregroundStyle(.orange)
                            Text(pattern)
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Button {
                                core.breakpoints.remove(pattern)
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.inset)
            }

            if !core.breakpoints.pausedRequests.isEmpty {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("\(core.breakpoints.pausedRequests.count) request(s) paused")
                        .font(.caption)
                    Spacer()
                    Button("Resume All") {
                        core.breakpoints.resolveAll(action: .resume)
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.1))
            }
        }
    }

    private func addPattern() {
        let pattern = newPattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return }
        core.breakpoints.add(pattern)
        newPattern = ""
    }
}

@available(macOS 14, *)
struct BreakpointsView_Previews: PreviewProvider {
    static var previews: some View {
        BreakpointsView()
            .environment(AppCore.preview())
            .frame(width: 500, height: 400)
    }
}

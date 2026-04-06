import SwiftUI
import PryKit

@available(macOS 14, *)
@MainActor
struct BreakpointListView: View {
    @Environment(BreakpointUIManager.self) private var breakpoints
    @State private var newPattern: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Breakpoints")
                    .font(.headline)
                Spacer()
                if !breakpoints.patterns.isEmpty {
                    Button {
                        breakpoints.clearAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear All")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Add pattern field
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

            if breakpoints.patterns.isEmpty {
                ContentUnavailableView(
                    "No Breakpoints",
                    systemImage: "pause.circle",
                    description: Text("Add a URL pattern to pause matching requests")
                )
            } else {
                List {
                    ForEach(breakpoints.patterns, id: \.self) { pattern in
                        HStack {
                            Image(systemName: "pause.circle")
                                .foregroundStyle(.orange)
                            Text(pattern)
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Button {
                                breakpoints.remove(pattern)
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

            // Paused requests count
            if !breakpoints.pausedRequests.isEmpty {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("\(breakpoints.pausedRequests.count) request(s) paused")
                        .font(.caption)
                    Spacer()
                    Button("Resume All") {
                        breakpoints.resumeAll()
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
        breakpoints.add(pattern)
        newPattern = ""
    }
}

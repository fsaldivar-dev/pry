import SwiftUI
import PryKit
import PryLib

@available(macOS 14, *)
struct BreakpointListView: View {
    @Environment(BreakpointUIManager.self) private var breakpoints
    @Environment(\.dismiss) private var dismiss

    @State private var newPattern = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Breakpoints")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if breakpoints.patterns.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "pause.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No breakpoints set")
                        .foregroundStyle(.secondary)
                    Text("Add a URL pattern to pause matching requests")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Divider()

            // Add new breakpoint
            HStack {
                TextField("URL pattern (e.g. /api/users)", text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit { addBreakpoint() }
                Button("Add") { addBreakpoint() }
                    .disabled(newPattern.isEmpty)
            }
            .padding()

            // Actions
            HStack {
                if !breakpoints.pausedRequests.isEmpty {
                    Button("Resume All") {
                        breakpoints.resumeAll()
                    }
                }
                Spacer()
                Button("Clear All", role: .destructive) {
                    breakpoints.clearAll()
                }
                .disabled(breakpoints.patterns.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    private func addBreakpoint() {
        guard !newPattern.isEmpty else { return }
        breakpoints.add(newPattern)
        newPattern = ""
    }
}

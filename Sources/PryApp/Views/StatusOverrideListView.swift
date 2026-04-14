import SwiftUI
import PryKit

@available(macOS 14, *)
@MainActor
struct StatusOverrideListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StatusOverrideUIManager.self) private var overrideManager
    @State private var newPattern = ""
    @State private var newStatus = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Status Overrides")
                    .font(.headline)
                Spacer()
                if !overrideManager.overrides.isEmpty {
                    Button {
                        overrideManager.clearAll()
                    } label: {
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

            // Add form
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("URL pattern (e.g. /api/login)", text: $newPattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                    TextField("Status", text: $newStatus)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .font(.system(size: 12, design: .monospaced))

                    Button("Add") {
                        addOverride()
                    }
                    .disabled(newPattern.isEmpty || UInt(newStatus) == nil)
                }

                // Quick-add buttons
                HStack(spacing: 4) {
                    Text("Quick:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach([400, 401, 403, 404, 429, 500, 503], id: \.self) { code in
                        Button("\(code)") {
                            newStatus = "\(code)"
                            if !newPattern.isEmpty { addOverride() }
                        }
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if overrideManager.overrides.isEmpty {
                ContentUnavailableView(
                    "No Overrides",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Add a status override to simulate error responses")
                )
            } else {
                List {
                    ForEach(Array(overrideManager.overrides.enumerated()), id: \.offset) { _, override in
                        HStack {
                            Text(override.pattern)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)

                            Spacer()

                            Text("\(override.status)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(PryTheme.statusColorSwiftUI(override.status))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(PryTheme.statusColorSwiftUI(override.status).opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            Button {
                                overrideManager.remove(pattern: override.pattern)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func addOverride() {
        guard !newPattern.isEmpty, let status = UInt(newStatus) else { return }
        overrideManager.save(pattern: newPattern, status: status)
        newPattern = ""
        newStatus = ""
    }
}

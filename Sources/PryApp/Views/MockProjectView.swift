import SwiftUI
import PryKit
import PryLib

@available(macOS 14, *)
@MainActor
struct MockProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MockProjectUIManager.self) private var projectManager
    @State private var showEditor = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Mock Project")
                    .font(.headline)

                Text("\(projectManager.mocks.count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(PryTheme.accent.opacity(0.2))
                    .foregroundStyle(PryTheme.accent)
                    .clipShape(Capsule())

                Spacer()

                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Project Mock")

                if !projectManager.mocks.isEmpty {
                    Button {
                        projectManager.applyAll()
                    } label: {
                        Image(systemName: "arrow.right.circle")
                        Text("Apply")
                    }
                    .help("Apply all project mocks to proxy")

                    Button {
                        projectManager.clearAll()
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

            if projectManager.mocks.isEmpty {
                ContentUnavailableView(
                    "No Project Mocks",
                    systemImage: "folder",
                    description: Text("Add organized, persistent mocks for your project")
                )
            } else {
                List {
                    ForEach(projectManager.mocks, id: \.id) { mock in
                        ProjectMockRow(mock: mock) {
                            projectManager.remove(pattern: mock.pattern)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showEditor) {
            ProjectMockEditorView()
                .frame(minWidth: 450, minHeight: 350)
        }
    }
}

@available(macOS 14, *)
private struct ProjectMockRow: View {
    let mock: ProjectMock
    let onDelete: () -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack {
            // Method badge
            Text(mock.method ?? "ANY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(PryTheme.methodColor(mock.method).opacity(0.2))
                .foregroundStyle(PryTheme.methodColor(mock.method))
                .clipShape(RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 2) {
                Text(mock.pattern)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                Text(mock.body.prefix(80))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Status badge
            Text("\(mock.status)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(PryTheme.statusColorSwiftUI(mock.status))

            if let delay = mock.delay {
                Text("\(delay)ms")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .confirmationDialog(
                "Delete mock for \(mock.pattern)?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
    }

}

@available(macOS 14, *)
private struct ProjectMockEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MockProjectUIManager.self) private var projectManager
    @State private var pattern = ""
    @State private var bodyText = "{}"
    @State private var method = "GET"
    @State private var status: UInt = 200
    @State private var notes = ""

    private let methods = ["GET", "POST", "PUT", "PATCH", "DELETE"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Mock")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Form {
                TextField("Pattern (e.g. /api/users)", text: $pattern)
                    .font(.system(size: 12, design: .monospaced))

                Picker("Method", selection: $method) {
                    ForEach(methods, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }

                TextField("Status Code", value: $status, format: .number)

                Section("Response Body") {
                    TextEditor(text: $bodyText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 120)
                }

                TextField("Notes (optional)", text: $notes)
            }
            .padding(12)

            Divider()

            HStack {
                Spacer()
                Button("Save") {
                    let mock = ProjectMock(
                        pattern: pattern,
                        body: bodyText,
                        method: method,
                        status: status,
                        notes: notes.isEmpty ? nil : notes
                    )
                    try? projectManager.save(mock)
                    dismiss()
                }
                .disabled(pattern.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(12)
        }
    }
}

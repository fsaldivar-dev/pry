import SwiftUI
import PryKit

@available(macOS 14, *)
@MainActor
struct MockListView: View {
    @Environment(MockManager.self) private var mockManager
    @State private var showEditor = false
    @State private var editingPath: String?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Mocks")
                    .font(.headline)
                Spacer()
                Button {
                    editingPath = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Mock")

                if !mockManager.mocks.isEmpty {
                    Button {
                        mockManager.clearAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear All Mocks")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if mockManager.mocks.isEmpty {
                ContentUnavailableView(
                    "No Mocks",
                    systemImage: "theatermask.and.paintbrush",
                    description: Text("Add a mock to simulate API responses")
                )
            } else {
                List {
                    ForEach(mockManager.mocks.keys.sorted(), id: \.self) { path in
                        MockRow(
                            path: path,
                            response: mockManager.mocks[path] ?? "",
                            onEdit: {
                                editingPath = path
                                showEditor = true
                            },
                            onDelete: {
                                mockManager.remove(path: path)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showEditor) {
            MockEditorView(existingPath: editingPath)
        }
    }
}

@available(macOS 14, *)
private struct MockRow: View {
    let path: String
    let response: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(path)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                Text(response)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .confirmationDialog(
                "Delete mock for \(path)?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
    }
}

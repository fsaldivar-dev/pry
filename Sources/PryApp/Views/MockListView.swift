import SwiftUI
import PryKit

@available(macOS 14, *)
struct MockListView: View {
    @Environment(MockManager.self) private var mocks
    @Environment(\.dismiss) private var dismiss

    @State private var newPath = ""
    @State private var newResponse = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Mock Responses")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Existing mocks
            if mocks.mocks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "theatermask.and.paintbrush")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No mocks configured")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(mocks.mocks.keys.sorted()), id: \.self) { path in
                        HStack {
                            Text(path)
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Text(mocks.mocks[path] ?? "")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Divider()

            // Add new mock
            HStack {
                TextField("Path (e.g. /api/test)", text: $newPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                TextField("Response JSON", text: $newResponse)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Button("Add") {
                    guard !newPath.isEmpty, !newResponse.isEmpty else { return }
                    mocks.save(path: newPath, response: newResponse)
                    newPath = ""
                    newResponse = ""
                }
                .disabled(newPath.isEmpty || newResponse.isEmpty)
            }
            .padding()

            // Clear all
            HStack {
                Spacer()
                Button("Clear All", role: .destructive) {
                    mocks.clearAll()
                }
                .disabled(mocks.mocks.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }
}

import SwiftUI

/// Banner rojo que aparece cuando hay una request pausada activa.
@available(macOS 14, *)
struct PausedRequestBanner: View {
    let method: String
    let url: String

    var body: some View {
        HStack {
            Image(systemName: "pause.circle.fill")
            Text("REQUEST PAUSED")
                .fontWeight(.bold)
            Text("— \(method) \(url)")
                .lineLimit(1)
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red)
    }
}

/// Editor modal para una `PausedRequest`. El usuario puede editar headers/body
/// y elegir entre resume / modify / cancel. La acción se envía al
/// `BreakpointStore` que resuelve la continuation subyacente y destraba el chain.
@available(macOS 14, *)
@MainActor
struct PausedRequestEditorView: View {
    @Environment(AppCore.self) private var core
    let pausedRequest: PausedRequest

    @State private var editedHeaders: [(String, String)]
    @State private var editedBody: String

    init(pausedRequest: PausedRequest) {
        self.pausedRequest = pausedRequest
        _editedHeaders = State(initialValue: pausedRequest.headers)
        _editedBody = State(initialValue: pausedRequest.body ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            PausedRequestBanner(method: pausedRequest.method, url: pausedRequest.url)

            HSplitView {
                // Left: editable request
                Form {
                    Section("Headers") {
                        ForEach(Array(editedHeaders.enumerated()), id: \.offset) { index, _ in
                            HStack {
                                TextField("Name", text: binding(for: index, component: .name))
                                    .font(.system(size: 11, design: .monospaced))
                                TextField("Value", text: binding(for: index, component: .value))
                                    .font(.system(size: 11, design: .monospaced))
                                Button(role: .destructive) {
                                    editedHeaders.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Button("Add Header") {
                            editedHeaders.append(("", ""))
                        }
                    }

                    Section("Body") {
                        TextEditor(text: $editedBody)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(minHeight: 200)
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 350)

                // Right: preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview").font(.headline)

                    GroupBox("Request") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(pausedRequest.method) \(pausedRequest.url)")
                                .font(.system(size: 12, design: .monospaced))
                            Text("Host: \(pausedRequest.host)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Headers (\(editedHeaders.count))") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(editedHeaders.enumerated()), id: \.offset) { _, header in
                                    Text("\(header.0): \(header.1)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                    }

                    if !editedBody.isEmpty {
                        GroupBox("Body") {
                            Text(String(editedBody.prefix(500)))
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Spacer()
                }
                .padding()
                .frame(minWidth: 250)
            }

            Divider()

            HStack {
                Button("Cancel Request", role: .destructive) {
                    core.breakpoints.resolve(id: pausedRequest.id, action: .cancel)
                }

                Spacer()

                Button("Resume Original") {
                    core.breakpoints.resolve(id: pausedRequest.id, action: .resume)
                }

                Button("Send Modified") {
                    core.breakpoints.resolve(id: pausedRequest.id, action: .modify(
                        headers: editedHeaders,
                        body: editedBody.isEmpty ? nil : editedBody
                    ))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private enum HeaderComponent { case name, value }

    private func binding(for index: Int, component: HeaderComponent) -> Binding<String> {
        Binding(
            get: {
                guard index < editedHeaders.count else { return "" }
                switch component {
                case .name: return editedHeaders[index].0
                case .value: return editedHeaders[index].1
                }
            },
            set: { newValue in
                guard index < editedHeaders.count else { return }
                switch component {
                case .name: editedHeaders[index].0 = newValue
                case .value: editedHeaders[index].1 = newValue
                }
            }
        )
    }
}

@available(macOS 14, *)
struct PausedRequestEditorView_Previews: PreviewProvider {
    static var previews: some View {
        PausedRequestEditorView(pausedRequest: PausedRequest(
            id: UUID(),
            method: "POST",
            url: "/api/login",
            host: "api.myapp.com",
            headers: [("Content-Type", "application/json"), ("Authorization", "Bearer xxx")],
            body: "{\"username\":\"test\"}",
            timestamp: Date()
        ))
        .environment(AppCore.preview())
        .frame(width: 800, height: 500)
    }
}

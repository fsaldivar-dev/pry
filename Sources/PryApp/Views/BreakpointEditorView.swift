import SwiftUI
import PryKit
import PryLib

@available(macOS 14, *)
struct BreakpointEditorView: View {
    let pausedRequest: PausedRequest
    @Environment(BreakpointUIManager.self) private var breakpoints

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Paused Request")
                    .font(.headline)
                Spacer()
                Button("Resume") {
                    breakpoints.resume(id: pausedRequest.id, action: .resume)
                }
                .keyboardShortcut(.return, modifiers: .command)
                Button("Cancel", role: .destructive) {
                    breakpoints.resume(id: pausedRequest.id, action: .cancel)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Method") {
                        Text(pausedRequest.method)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    LabeledContent("URL") {
                        Text(pausedRequest.url)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    LabeledContent("Host") {
                        Text(pausedRequest.host)
                            .font(.system(size: 12, design: .monospaced))
                    }

                    if !pausedRequest.headers.isEmpty {
                        Text("Headers")
                            .font(.subheadline)
                            .padding(.top, 4)
                        ForEach(Array(pausedRequest.headers.enumerated()), id: \.offset) { _, header in
                            HStack {
                                Text(header.0)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.blue)
                                Text(header.1)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(2)
                            }
                        }
                    }

                    if let body = pausedRequest.body, !body.isEmpty {
                        Text("Body")
                            .font(.subheadline)
                            .padding(.top, 4)
                        Text(body)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

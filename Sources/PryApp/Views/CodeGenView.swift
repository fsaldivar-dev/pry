import SwiftUI
import PryKit
import PryLib

@available(macOS 14, *)
@MainActor
struct CodeGenView: View {
    let request: RequestStore.CapturedRequest

    @State private var selectedLanguage: CodeLanguage = .curl
    @State private var generatedCode: String = ""

    enum CodeLanguage: String, CaseIterable, Identifiable {
        case curl = "cURL"
        case swift = "Swift"
        case python = "Python"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(CodeLanguage.allCases) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 250)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(generatedCode, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .help("Copy to Clipboard")
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollView {
                Text(generatedCode)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .onChange(of: selectedLanguage) { regenerate() }
        .onAppear { regenerate() }
    }

    private func regenerate() {
        // Detect HTTPS by URL scheme, port 443, or CONNECT tunnel origin
        let isHTTPS = request.url.lowercased().hasPrefix("https") ||
                      request.host.hasSuffix(":443") ||
                      request.isTunnel
        switch selectedLanguage {
        case .curl:
            generatedCode = CurlGenerator.generate(from: request, https: isHTTPS)
        case .swift:
            generatedCode = SwiftGenerator.generate(from: request, https: isHTTPS)
        case .python:
            generatedCode = PythonGenerator.generate(from: request, https: isHTTPS)
        }
    }
}

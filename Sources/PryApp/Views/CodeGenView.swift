import SwiftUI
import PryLib

@available(macOS 14, *)
struct CodeGenView: View {
    let request: RequestStore.CapturedRequest

    enum Language: String, CaseIterable {
        case swift = "Swift"
        case python = "Python"
    }

    @State private var selectedLanguage: Language = .swift

    private var generatedCode: String {
        switch selectedLanguage {
        case .swift:
            return SwiftGenerator.generate(from: request)
        case .python:
            return PythonGenerator.generate(from: request)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(Language.allCases, id: \.self) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(generatedCode, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                Text(generatedCode)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }
}

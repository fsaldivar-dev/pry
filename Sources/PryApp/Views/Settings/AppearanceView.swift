import SwiftUI

@available(macOS 14, *)
struct AppearanceView: View {
    @AppStorage("pry.fontSize") private var fontSize: Double = 11
    @AppStorage("pry.monoFont") private var useMonoFont = true
    @AppStorage("pry.colorScheme") private var colorSchemePreference = "system"

    var body: some View {
        Form {
            Section("Font") {
                HStack {
                    Text("Font Size")
                    Slider(value: $fontSize, in: 9...16, step: 1)
                    Text("\(Int(fontSize))pt")
                        .frame(width: 40)
                        .monospacedDigit()
                }

                Toggle("Use monospaced font for code", isOn: $useMonoFont)

                Text("Preview:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("GET /api/users → 200 OK")
                    .font(.system(size: CGFloat(fontSize), design: useMonoFont ? .monospaced : .default))
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Section("Theme") {
                Picker("Color Scheme", selection: $colorSchemePreference) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)

                Text("Changes take effect immediately")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Engine", value: "PryLib + SwiftNIO")

                Link("GitHub Repository",
                     destination: URL(string: "https://github.com/fsaldivar-dev/pry")!)
            }
        }
        .formStyle(.grouped)
    }
}

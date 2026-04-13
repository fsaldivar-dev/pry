import SwiftUI
import PryLib

@available(macOS 14, *)
struct QueryTabView: View {
    let request: RequestStore.CapturedRequest

    private var queryItems: [(name: String, value: String)] {
        guard let comps = URLComponents(string: "http://\(request.host)\(request.url)"),
              let items = comps.queryItems else { return [] }
        return items.map { (name: $0.name, value: $0.value ?? "") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Query Parameters")
                    .font(.headline)
                    .padding(.bottom, 4)

                if queryItems.isEmpty {
                    Text("No query parameters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        ForEach(Array(queryItems.enumerated()), id: \.offset) { _, item in
                            GridRow {
                                Text(item.name)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.accentColor)
                                    .textSelection(.enabled)
                                Text(item.value)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

import SwiftUI
import PryLib

@available(macOS 14, *)
struct GraphQLView: View {
    let request: RequestStore.CapturedRequest

    private var info: GraphQLInfo? {
        GraphQLDetector.detect(body: request.requestBody)
    }

    var body: some View {
        ScrollView {
            if let info = info {
                VStack(alignment: .leading, spacing: 16) {
                    if let opName = info.operationName {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Operation")
                                .font(.headline)
                            Text(opName)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Query")
                            .font(.headline)
                        Text(info.query)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    if let vars = info.variables {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Variables")
                                .font(.headline)
                            Text(vars)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No GraphQL data detected")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }
}

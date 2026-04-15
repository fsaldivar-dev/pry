import SwiftUI
import PryLib

@available(macOS 14, *)
struct GraphQLView: View {
    let request: RequestStore.CapturedRequest

    private var parsed: GraphQLInfo? {
        GraphQLDetector.detect(body: request.requestBody)
    }

    var body: some View {
        if let gql = parsed {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Operation") {
                        Text(gql.operationName ?? "Anonymous")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(gql.operationName != nil ? .primary : .secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Query")
                            .font(.headline)
                        Text(gql.query)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(PryTheme.bgPanel)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    if let vars = gql.variables, !vars.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Variables")
                                .font(.headline)
                            JSONSyntaxView(json: vars)
                                .frame(maxHeight: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "Not a GraphQL Request",
                systemImage: "questionmark.diamond",
                description: Text("This request does not contain a GraphQL query")
            )
        }
    }
}

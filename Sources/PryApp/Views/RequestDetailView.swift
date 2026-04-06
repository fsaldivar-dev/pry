import SwiftUI
import PryKit
import PryLib

@available(macOS 14, *)
struct RequestDetailView: View {
    @Environment(RequestStoreWrapper.self) private var store
    @Environment(BreakpointUIManager.self) private var breakpoints

    var body: some View {
        // If there's a paused request, show the editor
        if let paused = breakpoints.pausedRequests.first {
            BreakpointEditorView(pausedRequest: paused)
        } else if let request = store.selectedRequest {
            TabView {
                HeadersTabView(request: request)
                    .tabItem { Label("Headers", systemImage: "list.bullet") }
                BodyTabView(request: request)
                    .tabItem { Label("Body", systemImage: "doc.text") }
                QueryTabView(request: request)
                    .tabItem { Label("Query", systemImage: "questionmark.circle") }
                CookiesTabView(request: request)
                    .tabItem { Label("Cookies", systemImage: "birthday.cake") }
                RawTabView(request: request)
                    .tabItem { Label("Raw", systemImage: "chevron.left.forwardslash.chevron.right") }
                CodeGenView(request: request)
                    .tabItem { Label("Code", systemImage: "curlybraces") }

                // GraphQL tab — only if detected
                if GraphQLDetector.detect(body: request.requestBody) != nil {
                    GraphQLView(request: request)
                        .tabItem { Label("GraphQL", systemImage: "point.3.connected.trianglepath.dotted") }
                }
            }
            .padding(8)
        } else {
            ContentUnavailableView(
                "Select a Request",
                systemImage: "cursorarrow.click",
                description: Text("Choose a request from the list to inspect its details")
            )
        }
    }
}

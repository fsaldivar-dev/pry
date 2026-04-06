import SwiftUI
import PryKit
import PryLib

@available(macOS 14, *)
struct RequestDetailView: View {
    @Environment(RequestStoreWrapper.self) private var store

    var body: some View {
        if let request = store.selectedRequest {
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

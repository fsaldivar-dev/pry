import SwiftUI
import PryKit
import PryLib

/// Bottom detail panel — segmented picker navigation replaces TabView.
@available(macOS 14, *)
struct DetailPanelView: View {
    @Environment(RequestStoreWrapper.self) private var store
    @Environment(BreakpointUIManager.self) private var breakpoints

    enum Tab: String, CaseIterable {
        case headers  = "Headers"
        case body     = "Body"
        case query    = "Query"
        case cookies  = "Cookies"
        case raw      = "Raw"
        case code     = "Code"
        case graphql  = "GraphQL"
    }

    @State private var selectedTab: Tab = .headers

    var body: some View {
        if let paused = breakpoints.pausedRequests.first {
            BreakpointEditorView(pausedRequest: paused)
        } else if let request = store.selectedRequest {
            VStack(spacing: 0) {
                // Segmented picker bar
                HStack {
                    Picker("", selection: $selectedTab) {
                        let tabs = visibleTabs(for: request)
                        ForEach(tabs, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.bar)

                Divider()

                // Tab content
                Group {
                    switch selectedTab {
                    case .headers:  HeadersTabView(request: request)
                    case .body:     BodyTabView(request: request)
                    case .query:    QueryTabView(request: request)
                    case .cookies:  CookiesTabView(request: request)
                    case .raw:      RawTabView(request: request)
                    case .code:     CodeGenView(request: request)
                    case .graphql:  GraphQLView(request: request)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onChange(of: request.id) {
                // Keep selected tab when switching between requests (only reset if tab no longer visible)
                let visible = visibleTabs(for: request)
                if !visible.contains(selectedTab) {
                    selectedTab = .headers
                }
            }
        } else {
            ContentUnavailableView(
                "Select a Request",
                systemImage: "cursorarrow.click",
                description: Text("Choose a request from the list to inspect its details")
            )
        }
    }

    private func visibleTabs(for request: RequestStore.CapturedRequest) -> [Tab] {
        var tabs: [Tab] = [.headers, .body, .query, .cookies, .raw, .code]
        if GraphQLDetector.detect(body: request.requestBody) != nil {
            tabs.append(.graphql)
        }
        return tabs
    }
}

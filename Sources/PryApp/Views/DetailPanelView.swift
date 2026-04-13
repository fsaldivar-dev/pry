import SwiftUI
import PryKit
import PryLib

/// Bottom detail panel with underline tab navigation.
@available(macOS 14, *)
public struct DetailPanelView: View {
    @Environment(RequestStoreWrapper.self) private var store
    @Environment(BreakpointUIManager.self) private var breakpoints

    public enum Tab: String, CaseIterable {
        case headers  = "Headers"
        case body     = "Body"
        case query    = "Query"
        case cookies  = "Cookies"
        case raw      = "Raw"
        case code     = "Code"
        case graphql  = "GraphQL"
    }

    @State private var selectedTab: Tab = .headers

    public init() { }

    public var body: some View {
        if let paused = breakpoints.pausedRequests.first {
            BreakpointEditorView(pausedRequest: paused)
        } else if let request = store.selectedRequest {
            VStack(spacing: 0) {
                // Underline tab bar
                UnderlineTabBar(
                    selectedTab: $selectedTab,
                    visibleTabs: visibleTabs(for: request),
                    onCopyCurl: {
                        let curl = CurlGenerator.generate(from: request)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(curl, forType: .string)
                    }
                )

                Divider().opacity(0.3)

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
                let visible = visibleTabs(for: request)
                if !visible.contains(selectedTab) {
                    selectedTab = .headers
                }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "cursorarrow.click")
                    .foregroundStyle(PryTheme.accent.opacity(0.4))
                Text("Select a request to inspect")
                    .foregroundStyle(PryTheme.textSecondary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    func visibleTabs(for request: RequestStore.CapturedRequest) -> [Tab] {
        var tabs: [Tab] = [.headers, .body, .query, .cookies, .raw, .code]
        if GraphQLDetector.detect(body: request.requestBody) != nil {
            tabs.append(.graphql)
        }
        return tabs
    }
}

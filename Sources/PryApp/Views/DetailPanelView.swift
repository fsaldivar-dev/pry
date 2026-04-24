import SwiftUI
import AppKit
import PryKit
import PryLib

/// Bottom detail panel — segmented picker navigation with Copy cURL action.
@available(macOS 14, *)
public struct DetailPanelView: View {
    @Environment(RequestStoreWrapper.self) private var store
    @Environment(AppCore.self) private var core

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
        if let paused = core.breakpoints.pausedRequests.first {
            PausedRequestEditorView(pausedRequest: paused)
        } else if let request = store.selectedRequest {
            VStack(spacing: 0) {
                // Segmented picker bar with Copy cURL
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
                    Button {
                        let curl = CurlGenerator.generate(from: request)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(curl, forType: .string)
                    } label: {
                        Label("Copy cURL", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(PryTheme.bgHeader)

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
            HStack(spacing: 6) {
                Image(systemName: "cursorarrow.click")
                    .foregroundStyle(PryTheme.accent.opacity(0.4))
                Text("Select a request to inspect")
                    .foregroundStyle(PryTheme.textSecondary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PryTheme.bgPanel)
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

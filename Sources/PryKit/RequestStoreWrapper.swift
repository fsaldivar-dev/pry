import Foundation
import Observation
import PryLib

/// Source filter for sidebar selection.
@available(macOS 14, *)
public enum SourceFilter: Hashable, Sendable {
    case all
    case app(String)
    case host(app: String, host: String)
}

/// @Observable bridge over RequestStore for SwiftUI.
@available(macOS 14, *)
@Observable
@MainActor
public final class RequestStoreWrapper {
    public var requests: [RequestStore.CapturedRequest] = []
    public var selectedRequest: RequestStore.CapturedRequest?
    public var selectedSource: SourceFilter?
    public var filterText: String = ""
    public var filterMethod: String?
    public var filterStatus: ClosedRange<UInt>?

    private let store: RequestStore

    public var filteredRequests: [RequestStore.CapturedRequest] {
        var result = requests

        // Source filter from sidebar
        if let source = selectedSource {
            switch source {
            case .all:
                break
            case .app(let app):
                result = result.filter { $0.appName == app }
            case .host(let app, let host):
                result = result.filter { $0.appName == app && $0.host == host }
            }
        }

        if let method = filterMethod {
            result = result.filter { $0.method.uppercased() == method.uppercased() }
        }
        if let range = filterStatus {
            result = result.filter { req in
                guard let code = req.statusCode else { return false }
                return range.contains(code)
            }
        }
        if !filterText.isEmpty {
            let lower = filterText.lowercased()
            result = result.filter {
                $0.url.lowercased().contains(lower) ||
                $0.host.lowercased().contains(lower)
            }
        }
        return result
    }

    public init(store: RequestStore = .shared) {
        self.store = store
        self.requests = store.getAll()

        store.onChange = { [weak self] in
            guard let self else { return }
            let all = store.getAll()
            Task { @MainActor in
                self.requests = all
            }
        }
    }
}

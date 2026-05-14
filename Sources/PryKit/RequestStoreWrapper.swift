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
///
/// Debounces updates from PryLib's RequestStore into the MainActor,
/// and caches the filtered result to avoid redundant iteration.
@available(macOS 14, *)
@Observable
@MainActor
public final class RequestStoreWrapper {
    // MARK: - Published state

    public var requests: [RequestStore.CapturedRequest] = [] {
        didSet { invalidateFilterCache() }
    }
    public var selectedRequest: RequestStore.CapturedRequest?
    public var selectedSource: SourceFilter? {
        didSet { invalidateFilterCache() }
    }
    public var filterText: String = "" {
        didSet { invalidateFilterCache() }
    }
    public var filterMethod: String? {
        didSet { invalidateFilterCache() }
    }
    public var filterStatus: ClosedRange<UInt>? {
        didSet { invalidateFilterCache() }
    }

    // MARK: - Filtered results (cached)

    /// Cached filtered requests. Recomputed only when inputs change.
    public var filteredRequests: [RequestStore.CapturedRequest] {
        if let cached = _cachedFiltered { return cached }
        let result = computeFiltered()
        _cachedFiltered = result
        return result
    }

    // MARK: - Private

    private let store: RequestStore
    private var updateTask: Task<Void, Never>?
    private var _cachedFiltered: [RequestStore.CapturedRequest]?

    private func invalidateFilterCache() {
        _cachedFiltered = nil
    }

    private func computeFiltered() -> [RequestStore.CapturedRequest] {
        var result = requests

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

    // MARK: - Public actions

    /// Clear all captured requests and reset selection.
    public func clear() {
        store.clear()
        requests = []
        selectedRequest = nil
        invalidateFilterCache()
    }

    // MARK: - Init

    public init(store: RequestStore = .shared) {
        self.store = store
        self.requests = store.getAll()

        store.onChange = { [weak self] in
            guard let self else { return }
            let all = store.getAll()
            // Cancel pending task to debounce rapid-fire updates
            self.updateTask?.cancel()
            self.updateTask = Task { @MainActor in
                guard !Task.isCancelled else { return }
                self.requests = all
            }
        }
    }
}

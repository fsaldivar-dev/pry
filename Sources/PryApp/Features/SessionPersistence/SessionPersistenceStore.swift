import Foundation
import Observation
import PryLib

/// Store de persistencia de sesión — feature del issue #91.
/// Observer pattern (igual que Recordings): subscribe al `EventBus`, no muta
/// el flow del proxy.
///
/// Cuando `isEnabled == true`:
/// - Recibe `RequestCapturedEvent` → guarda datos parciales en `pending`
/// - Recibe `ResponseReceivedEvent` → ensambla `PersistedSessionRequest` y
///   hace append al file (`~/.pry/sessions/last.jsonl`)
///
/// La toggle persiste en UserDefaults (default false por privacidad).
@available(macOS 14, *)
@Observable
@MainActor
public final class SessionPersistenceStore {
    // MARK: - Published state

    public var isEnabled: Bool {
        didSet {
            SessionPersistence.setEnabled(isEnabled)
            refreshStats()
        }
    }

    public private(set) var persistedCount: Int = 0
    public private(set) var persistedBytes: Int = 0

    // MARK: - Internal

    private let bus: EventBus
    private var pending: [Int: PendingData] = [:]

    nonisolated(unsafe) private var requestTask: Task<Void, Never>?
    nonisolated(unsafe) private var responseTask: Task<Void, Never>?

    private struct PendingData {
        let capturedAt: Date
        let method: String
        let host: String
        let url: String
        let headers: [(String, String)]
        let body: String?
    }

    public init(bus: EventBus) {
        self.bus = bus
        self.isEnabled = SessionPersistence.isEnabled()
        refreshStats()
        subscribeToBus()
    }

    deinit {
        requestTask?.cancel()
        responseTask?.cancel()
    }

    // MARK: - Actions

    /// Borra el file de sesión persistida + actualiza stats.
    public func clearPersisted() {
        SessionPersistence.clear()
        refreshStats()
    }

    /// Relee stats del disco (para cuando una operación externa los cambia).
    public func refreshStats() {
        persistedCount = SessionPersistence.currentCount()
        persistedBytes = SessionPersistence.currentSizeBytes()
    }

    // MARK: - Bus subscription

    private func subscribeToBus() {
        requestTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.bus.subscribe(to: RequestCapturedEvent.self) {
                await self.handleRequest(event)
            }
        }
        responseTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.bus.subscribe(to: ResponseReceivedEvent.self) {
                await self.handleResponse(event)
            }
        }
    }

    private func handleRequest(_ event: RequestCapturedEvent) {
        guard isEnabled else { return }
        pending[event.requestID] = PendingData(
            capturedAt: event.capturedAt,
            method: event.method,
            host: event.host,
            url: event.url,
            headers: event.headers,
            body: event.body
        )
    }

    private func handleResponse(_ event: ResponseReceivedEvent) {
        guard isEnabled else {
            pending.removeValue(forKey: event.requestID)
            return
        }
        guard let p = pending.removeValue(forKey: event.requestID) else { return }

        let record = PersistedSessionRequest(
            requestID: event.requestID,
            capturedAt: p.capturedAt,
            method: p.method,
            host: p.host,
            url: p.url,
            requestHeaders: p.headers,
            requestBody: p.body,
            statusCode: event.status,
            responseHeaders: event.headers,
            responseBody: event.body,
            latencyMs: event.latencyMs
        )
        SessionPersistence.append(record)
        refreshStats()
    }
}

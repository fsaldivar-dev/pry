import Foundation
import Observation
import PryLib

/// Store de grabaciones de tráfico. Feature "Recordings" del ADR-006 —
/// observer pattern puro: subscribe al `EventBus` y acumula `RecordingStep`s
/// locales. No usa `Recorder.shared` para su state — sólo para persistencia
/// (formato .pryrecording compatible con el legacy CLI).
///
/// Cuando está grabando:
/// - Recibe `RequestCapturedEvent` → guarda en `pendingRequests`
/// - Recibe `ResponseReceivedEvent` → forma `RecordingStep` y lo agrega a `steps`
///
/// Al hacer `stop()` serializa `Recording` a disco via `RecordingPersistence`.
@available(macOS 14, *)
@Observable
@MainActor
public final class RecordingsStore {
    // MARK: - Published state

    /// Si hay una grabación en curso.
    public private(set) var isRecording: Bool = false

    /// Nombre de la grabación actualmente activa (nil si no está grabando).
    public private(set) var currentRecordingName: String?

    /// Cantidad de steps acumulados en la grabación actual (útil para UI).
    public private(set) var currentStepCount: Int = 0

    /// Lista de nombres de grabaciones guardadas en disco.
    public private(set) var recordings: [String] = []

    // MARK: - Internal state

    private let bus: EventBus
    private var current: Recording?
    /// Map de requestID → datos de request pendientes de response.
    private var pendingRequests: [Int: PendingRequest] = [:]
    /// Dominios a filtrar (vacío = grabar todo).
    private var filterDomains: [String] = []

    nonisolated(unsafe) private var subscriptionTask: Task<Void, Never>?
    nonisolated(unsafe) private var responseTask: Task<Void, Never>?

    private struct PendingRequest {
        let startedAt: Date
        let method: String
        let url: String
        let host: String
        let headers: [CodableHeader]
        let body: String?
    }

    // MARK: - Init

    public init(bus: EventBus) {
        self.bus = bus
        reload()
        subscribeToBus()
    }

    deinit {
        subscriptionTask?.cancel()
        responseTask?.cancel()
    }

    // MARK: - Actions

    public func reload() {
        recordings = RecordingPersistence.list().sorted()
    }

    public func start(name: String, domains: [String] = []) {
        let sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return }
        current = Recording(name: sanitized)
        pendingRequests = [:]
        filterDomains = domains.map { $0.lowercased() }
        isRecording = true
        currentRecordingName = sanitized
        currentStepCount = 0
        publishChange()
    }

    @discardableResult
    public func stop() -> Recording? {
        guard var recording = current else { return nil }
        recording.stoppedAt = Date()
        try? RecordingPersistence.save(recording)
        let result = recording
        current = nil
        pendingRequests = [:]
        isRecording = false
        currentRecordingName = nil
        currentStepCount = 0
        reload()
        publishChange()
        return result
    }

    public func delete(name: String) {
        RecordingPersistence.delete(name: name)
        reload()
        publishChange()
    }

    public func load(name: String) -> Recording? {
        RecordingPersistence.load(name: name)
    }

    // MARK: - Bus subscription

    private func subscribeToBus() {
        subscriptionTask = Task { [weak self] in
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
        guard isRecording else { return }
        // Filtrar por dominio si está configurado.
        if !filterDomains.isEmpty {
            let h = event.host.lowercased()
            let matches = filterDomains.contains { d in
                h == d || h.hasSuffix(".\(d)")
            }
            guard matches else { return }
        }
        pendingRequests[event.requestID] = PendingRequest(
            startedAt: event.capturedAt,
            method: event.method,
            url: event.url,
            host: event.host,
            headers: event.headers.map { CodableHeader(name: $0.0, value: $0.1) },
            body: event.body
        )
    }

    private func handleResponse(_ event: ResponseReceivedEvent) {
        guard var recording = current,
              let pending = pendingRequests.removeValue(forKey: event.requestID) else { return }
        let step = RecordingStep(
            sequence: recording.steps.count + 1,
            timestamp: pending.startedAt,
            method: pending.method,
            url: pending.url,
            host: pending.host,
            requestHeaders: pending.headers,
            requestBody: pending.body,
            statusCode: event.status,
            responseHeaders: event.headers.map { CodableHeader(name: $0.0, value: $0.1) },
            responseBody: event.body,
            latencyMs: event.latencyMs
        )
        recording.steps.append(step)
        current = recording
        currentStepCount = recording.steps.count
    }

    private func publishChange() {
        let snapshot = recordings
        let recording = isRecording
        let bus = self.bus
        Task { await bus.publish(RecordingsChangedEvent(names: snapshot, isRecording: recording)) }
    }
}

import Foundation
import Observation
import PryLib

/// Acción de resume/modify/cancel que la UI entrega al store para destrabar una
/// request pausada. Se traduce a `InterceptResult` cuando la chain continúa.
@available(macOS 14, *)
public enum BreakpointAction: Sendable {
    case resume
    case modify(headers: [(String, String)]?, body: String?)
    case cancel
}

/// Snapshot público de una request pausada. Es lo que ve la UI — sin
/// continuations ni closures.
@available(macOS 14, *)
public struct PausedRequest: Identifiable, Sendable {
    public let id: UUID
    public let method: String
    public let url: String
    public let host: String
    public let headers: [(String, String)]
    public let body: String?
    public let timestamp: Date

    public init(
        id: UUID,
        method: String,
        url: String,
        host: String,
        headers: [(String, String)],
        body: String?,
        timestamp: Date
    ) {
        self.id = id
        self.method = method
        self.url = url
        self.host = host
        self.headers = headers
        self.body = body
        self.timestamp = timestamp
    }
}

/// Store de Breakpoints migrado a ADR-006.
///
/// Doble rol:
/// 1. **Patrones**: lista de URL/host patterns persistida a disco. Comparte archivo
///    con `BreakpointsStore` legacy (PryLib) — CLI (`pry break`) y PryApp leen la
///    misma fuente de verdad.
/// 2. **Runtime pause/resume**: cuando un `BreakpointInterceptor` retorna
///    `.pause(resolution:)`, el store encola el snapshot en `pausedRequests` y
///    parquea una `CheckedContinuation`. La UI resuelve vía `resolve(id:action:)`
///    y el chain continúa con el `InterceptResult` correspondiente.
///
/// `CheckedContinuation` sólo puede resumirse una vez — guardamos el dictionary
/// por id y lo sacamos al resolver para evitar doble resume (ej. doble-click).
@available(macOS 14, *)
@Observable
@MainActor
public final class BreakpointsStore {
    /// Lista de patterns activos.
    public private(set) var patterns: [String] = []

    /// Requests actualmente pausadas, en orden de llegada.
    public private(set) var pausedRequests: [PausedRequest] = []

    private let storagePath: String
    private let bus: EventBus

    @ObservationIgnored
    private var pending: [UUID: PendingEntry] = [:]

    private struct PendingEntry {
        let continuation: CheckedContinuation<InterceptResult, Never>
        let ctx: RequestContext
    }

    public init(storagePath: String, bus: EventBus) {
        self.storagePath = storagePath
        self.bus = bus
        reload()
    }

    // MARK: - Patterns

    /// Agrega un pattern. Trim + dedupe automáticos; no-op si está vacío o ya existe.
    public func add(_ pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !patterns.contains(trimmed) else { return }
        patterns.append(trimmed)
        persist()
    }

    /// Quita un pattern de la lista. No-op si no existe.
    public func remove(_ pattern: String) {
        let before = patterns.count
        patterns.removeAll { $0 == pattern }
        if patterns.count != before { persist() }
    }

    /// Limpia todos los patterns de breakpoints.
    public func clearAll() {
        guard !patterns.isEmpty else { return }
        patterns.removeAll()
        persist()
    }

    /// Retorna `true` si `url` o `host` matchea algún pattern. Soporta glob `*`.
    public func isMatch(url: String, host: String) -> Bool {
        for pattern in patterns {
            if matches(pattern: pattern, url: url, host: host) { return true }
        }
        return false
    }

    private func matches(pattern: String, url: String, host: String) -> Bool {
        if pattern.contains("*") {
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
            let regexPattern = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*")
            guard let regex = try? NSRegularExpression(pattern: regexPattern) else { return false }
            let urlRange = NSRange(url.startIndex..., in: url)
            let hostRange = NSRange(host.startIndex..., in: host)
            return regex.firstMatch(in: url, range: urlRange) != nil
                || regex.firstMatch(in: host, range: hostRange) != nil
        }
        return url.contains(pattern) || host.contains(pattern)
    }

    // MARK: - Runtime pause/resume

    /// Llamado por `BreakpointInterceptor` cuando una request matchea. Encola el
    /// snapshot, publica `RequestPausedEvent`, y suspende hasta que la UI llame
    /// `resolve(id:action:)`. Retorna el `InterceptResult` correspondiente.
    public func enqueue(ctx: RequestContext, body: String? = nil) async -> InterceptResult {
        let snapshot = PausedRequest(
            id: ctx.id,
            method: ctx.method,
            url: ctx.path,
            host: ctx.host,
            headers: ctx.headers.map { ($0.key, $0.value) },
            body: body,
            timestamp: Date()
        )
        pausedRequests.append(snapshot)
        let bus = self.bus
        let id = ctx.id
        Task { await bus.publish(RequestPausedEvent(requestID: id)) }

        return await withCheckedContinuation { continuation in
            pending[ctx.id] = PendingEntry(continuation: continuation, ctx: ctx)
        }
    }

    /// Resume una request pausada. No-op si el id no existe (guard anti doble resume).
    public func resolve(id: UUID, action: BreakpointAction) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        pausedRequests.removeAll { $0.id == id }
        entry.continuation.resume(returning: translate(action: action, ctx: entry.ctx))
    }

    /// Resume todas las requests pausadas con la acción dada (default `.resume`).
    public func resolveAll(action: BreakpointAction = .resume) {
        let ids = pausedRequests.map(\.id)
        for id in ids { resolve(id: id, action: action) }
    }

    /// Traduce una `BreakpointAction` al `InterceptResult` correspondiente. Body
    /// editing vía `.modify(body:)` queda como follow-up: `bodyRef` es un closure
    /// asíncrono y sustituirlo por uno que entregue el body modificado requiere
    /// plomería adicional. Por ahora el body del `.modify` se ignora.
    private func translate(action: BreakpointAction, ctx: RequestContext) -> InterceptResult {
        switch action {
        case .resume:
            return .pass
        case .cancel:
            return .shortCircuit(.forbidden(reason: "Cancelled at breakpoint"))
        case .modify(let newHeaders, _):
            var mutated = ctx
            if let newHeaders = newHeaders {
                for (name, value) in newHeaders {
                    mutated.headers[name] = value
                }
            }
            return .transform(mutated)
        }
    }

    // MARK: - Persistence

    private func reload() {
        guard let content = try? String(contentsOfFile: storagePath, encoding: .utf8) else {
            patterns = []
            return
        }
        patterns = content
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func persist() {
        let content = patterns.joined(separator: "\n") + (patterns.isEmpty ? "" : "\n")
        try? content.write(toFile: storagePath, atomically: true, encoding: .utf8)
    }
}

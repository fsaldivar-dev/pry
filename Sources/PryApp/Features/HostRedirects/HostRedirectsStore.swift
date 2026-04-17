import Foundation
import Observation
import PryLib

/// Representa una regla de redirect host→host. Cuando una request va a `sourceHost`,
/// el proxy la reenvía a `targetHost` (útil para test→stage, prod→staging, etc.).
///
/// Se persiste en formato `source\ttarget` por línea, compatible con el legacy
/// `MapRemote` (PryLib) — ambos leen y escriben el mismo archivo cuando
/// `AppCore` inyecta `StoragePaths.redirectsFile`.
public struct HostRedirect: Sendable, Equatable {
    public let sourceHost: String
    public let targetHost: String

    public init(sourceHost: String, targetHost: String) {
        self.sourceHost = sourceHost
        self.targetHost = targetHost
    }
}

/// Store de host redirects. Reemplaza progresivamente a `MapRemote`
/// (PryLib legacy) en el contexto de PryApp.
///
/// Persiste a un archivo configurable (`AppCore` pasa `StoragePaths.redirectsFile`).
/// Formato: `source\ttarget` por línea, compatible con el legacy para coexistencia CLI.
/// Matching case-insensitive contra el host de la request.
@available(macOS 14, *)
@Observable
@MainActor
public final class HostRedirectsStore {
    /// Lista actual de redirects.
    public private(set) var redirects: [HostRedirect] = []

    private let storagePath: String
    private let bus: EventBus

    /// - Parameters:
    ///   - storagePath: archivo donde persistir los redirects (formato `source\ttarget`).
    ///     `AppCore` pasa el path canónico; los tests inyectan temp dirs.
    ///   - bus: bus de eventos al que publicar `HostRedirectsChangedEvent` tras mutaciones.
    public init(storagePath: String, bus: EventBus) {
        self.storagePath = storagePath
        self.bus = bus
        reload()
    }

    // MARK: - Actions

    /// Agrega un redirect. Trim + lowercase automático. No-op si alguno está vacío.
    /// Si ya existe un redirect con el mismo source, lo reemplaza con el nuevo target.
    public func add(source: String, target: String) {
        let src = sanitize(source)
        let tgt = sanitize(target)
        guard !src.isEmpty, !tgt.isEmpty else { return }
        if let idx = redirects.firstIndex(where: { $0.sourceHost == src }) {
            // Dedup: mismo source reemplaza target.
            guard redirects[idx].targetHost != tgt else { return }
            redirects[idx] = HostRedirect(sourceHost: src, targetHost: tgt)
        } else {
            redirects.append(HostRedirect(sourceHost: src, targetHost: tgt))
        }
        persist()
        publishChange()
    }

    /// Quita el redirect con el source dado. No-op si no existe.
    public func remove(source: String) {
        let src = sanitize(source)
        let before = redirects.count
        redirects.removeAll { $0.sourceHost == src }
        if redirects.count != before {
            persist()
            publishChange()
        }
    }

    /// Vacía la lista completa.
    public func clear() {
        guard !redirects.isEmpty else { return }
        redirects.removeAll()
        persist()
        publishChange()
    }

    private func sanitize(_ raw: String) -> String {
        raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    private func publishChange() {
        let snapshot = redirects.map { ($0.sourceHost, $0.targetHost) }
        let bus = self.bus
        Task { await bus.publish(HostRedirectsChangedEvent(redirects: snapshot)) }
    }

    // MARK: - Matching

    /// Retorna el target host si alguna regla matchea `host` (case-insensitive
    /// contra igualdad exacta de hostname). Retorna `nil` si ningún redirect aplica.
    public func match(host: String) -> String? {
        let h = host.lowercased()
        for rule in redirects {
            if h == rule.sourceHost { return rule.targetHost }
        }
        return nil
    }

    // MARK: - Persistence

    private func reload() {
        guard let content = try? String(contentsOfFile: storagePath, encoding: .utf8) else {
            redirects = []
            return
        }
        redirects = content
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 1)
                guard parts.count == 2,
                      !parts[0].isEmpty,
                      !parts[1].isEmpty else { return nil }
                return HostRedirect(
                    sourceHost: String(parts[0]),
                    targetHost: String(parts[1])
                )
            }
    }

    private func persist() {
        let content = redirects.map { "\($0.sourceHost)\t\($0.targetHost)" }.joined(separator: "\n")
        let toWrite = redirects.isEmpty ? "" : content + "\n"
        try? toWrite.write(toFile: storagePath, atomically: true, encoding: .utf8)
    }
}

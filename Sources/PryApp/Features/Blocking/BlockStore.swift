import Foundation
import Observation

/// Store de dominios bloqueados. Reemplaza progresivamente a `BlockList` (PryLib legacy)
/// en el contexto de PryApp.
///
/// Persiste a un archivo configurable (por default usa el path que `AppCore` pasa via
/// `AppCore.blocksStoragePath` — mismo archivo que el legacy `BlockList`, garantizando
/// coexistencia con CLI). Formato: un dominio por línea. Wildcards se expresan como
/// `*.domain.com`.
@available(macOS 14, *)
@Observable
@MainActor
public final class BlockStore {
    /// Lista actual de dominios/patrones bloqueados.
    public private(set) var domains: [String] = []

    private let storagePath: String
    private let bus: EventBus

    /// - Parameters:
    ///   - storagePath: archivo donde persistir la lista (un dominio por línea).
    ///     `AppCore` pasa el path canónico; los tests inyectan temp dirs.
    ///   - bus: bus de eventos al que publicar `BlockListChangedEvent` tras mutaciones,
    ///     permitiendo a otros subscribers reaccionar sin acoplarse al store.
    public init(storagePath: String, bus: EventBus) {
        self.storagePath = storagePath
        self.bus = bus
        reload()
    }

    // MARK: - Actions

    /// Agrega un dominio. Lowercase + trim automáticos. No-op si está vacío o ya existe.
    public func add(_ domain: String) {
        let sanitized = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return }
        guard !domains.contains(sanitized) else { return }
        domains.append(sanitized)
        persist()
        publishChange()
    }

    /// Quita un dominio. No-op si no existe.
    public func remove(_ domain: String) {
        let sanitized = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let before = domains.count
        domains.removeAll { $0 == sanitized }
        if domains.count != before {
            persist()
            publishChange()
        }
    }

    /// Vacía la lista completa.
    public func clear() {
        guard !domains.isEmpty else { return }
        domains.removeAll()
        persist()
        publishChange()
    }

    private func publishChange() {
        let snapshot = domains
        let bus = self.bus
        Task { await bus.publish(BlockListChangedEvent(domains: snapshot)) }
    }

    /// Retorna `true` si `host` matchea algún patrón bloqueado.
    /// Soporta wildcard `*.domain.com` que matchea `domain.com` + cualquier subdominio.
    public func isBlocked(_ host: String) -> Bool {
        let h = host.lowercased()
        for pattern in domains {
            if pattern.hasPrefix("*.") {
                let suffix = String(pattern.dropFirst(1)) // incluye el punto: ".domain.com"
                let base = String(pattern.dropFirst(2))   // sin punto: "domain.com"
                if h == base || h.hasSuffix(suffix) { return true }
            } else if h == pattern {
                return true
            }
        }
        return false
    }

    // MARK: - Persistence

    private func reload() {
        guard let content = try? String(contentsOfFile: storagePath, encoding: .utf8) else {
            domains = []
            return
        }
        domains = content
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func persist() {
        let content = domains.joined(separator: "\n") + (domains.isEmpty ? "" : "\n")
        try? content.write(toFile: storagePath, atomically: true, encoding: .utf8)
    }
}

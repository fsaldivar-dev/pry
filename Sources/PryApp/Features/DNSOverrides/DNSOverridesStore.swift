import Foundation
import Observation
import PryLib

/// Representa un override de DNS: cuando una request apunta a `domain`, el proxy
/// debe conectar a `ip` en vez de hacer resolución real. Útil para enrutar tráfico
/// a servidores locales de dev/staging sin tocar `/etc/hosts`.
///
/// Se persiste en formato `domain\tip` por línea, compatible con el legacy
/// `DNSSpoofing` (PryLib) — ambos leen y escriben el mismo archivo cuando
/// `AppCore` inyecta `StoragePaths.dnsFile`.
public struct DNSOverride: Sendable, Equatable {
    public let domain: String
    public let ip: String

    public init(domain: String, ip: String) {
        self.domain = domain
        self.ip = ip
    }
}

/// Store de DNS overrides. Reemplaza progresivamente a `DNSSpoofing` (PryLib legacy)
/// en el contexto de PryApp.
///
/// Persiste a un archivo configurable. Formato: `domain\tip` por línea, compatible
/// con el legacy para coexistencia CLI. Matching exacto case-insensitive sobre el host.
@available(macOS 14, *)
@Observable
@MainActor
public final class DNSOverridesStore {
    /// Lista actual de overrides.
    public private(set) var overrides: [DNSOverride] = []

    private let storagePath: String
    private let bus: EventBus

    /// - Parameters:
    ///   - storagePath: archivo donde persistir los overrides (formato `domain\tip`).
    ///     `AppCore` pasa el path canónico; los tests inyectan temp dirs.
    ///   - bus: bus de eventos al que publicar `DNSOverridesChangedEvent` tras mutaciones.
    public init(storagePath: String, bus: EventBus) {
        self.storagePath = storagePath
        self.bus = bus
        reload()
    }

    // MARK: - Actions

    /// Agrega un override. Trim + lowercase del domain; trim del IP. No-op si
    /// alguno queda vacío o si el IP no contiene un `.` (validación mínima).
    /// Si ya existe un override con el mismo domain, lo reemplaza con el nuevo IP.
    public func add(domain: String, ip: String) {
        let sanitizedDomain = domain
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\t", with: "")
        let sanitizedIP = ip
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\t", with: "")
        guard !sanitizedDomain.isEmpty else { return }
        guard !sanitizedIP.isEmpty, sanitizedIP.contains(".") else { return }

        if let idx = overrides.firstIndex(where: { $0.domain == sanitizedDomain }) {
            guard overrides[idx].ip != sanitizedIP else { return }
            overrides[idx] = DNSOverride(domain: sanitizedDomain, ip: sanitizedIP)
        } else {
            overrides.append(DNSOverride(domain: sanitizedDomain, ip: sanitizedIP))
        }
        persist()
        publishChange()
    }

    /// Quita el override con el domain dado. No-op si no existe.
    public func remove(domain: String) {
        let sanitized = domain
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let before = overrides.count
        overrides.removeAll { $0.domain == sanitized }
        if overrides.count != before {
            persist()
            publishChange()
        }
    }

    /// Vacía la lista completa.
    public func clear() {
        guard !overrides.isEmpty else { return }
        overrides.removeAll()
        persist()
        publishChange()
    }

    // MARK: - Resolution

    /// Resuelve un host contra la lista de overrides. Matching exacto
    /// case-insensitive — devuelve la IP configurada si hay coincidencia, `nil`
    /// en caso contrario.
    public func resolve(host: String) -> String? {
        let lower = host.lowercased()
        for override in overrides where override.domain == lower {
            return override.ip
        }
        return nil
    }

    // MARK: - Persistence

    private func reload() {
        guard let content = try? String(contentsOfFile: storagePath, encoding: .utf8) else {
            overrides = []
            return
        }
        overrides = content
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                let domain = String(parts[0])
                let ip = String(parts[1])
                guard !domain.isEmpty, !ip.isEmpty else { return nil }
                return DNSOverride(domain: domain, ip: ip)
            }
    }

    private func persist() {
        let content = overrides.map { "\($0.domain)\t\($0.ip)" }.joined(separator: "\n")
        let toWrite = overrides.isEmpty ? "" : content + "\n"
        try? toWrite.write(toFile: storagePath, atomically: true, encoding: .utf8)
    }

    private func publishChange() {
        let snapshot = overrides.map { ($0.domain, $0.ip) }
        let bus = self.bus
        Task { await bus.publish(DNSOverridesChangedEvent(overrides: snapshot)) }
    }
}

import Foundation
import Observation
import PryLib

/// Representa una regla de status override: un patrón que matchea URL/host +
/// el status code con el que se debe responder inmediatamente.
///
/// Se persiste en formato `pattern\tstatus` por línea, compatible con el legacy
/// `StatusOverrideStore` (PryLib) — ambos leen y escriben el mismo archivo cuando
/// `AppCore` inyecta `StoragePaths.overridesFile`.
public struct StatusOverride: Sendable, Equatable {
    public let pattern: String
    public let status: Int

    public init(pattern: String, status: Int) {
        self.pattern = pattern
        self.status = status
    }
}

/// Store de status overrides. Reemplaza progresivamente a `StatusOverrideStore`
/// (PryLib legacy) en el contexto de PryApp.
///
/// Persiste a un archivo configurable (`AppCore.overridesStoragePath`). Formato:
/// `pattern\tstatus` por línea, compatible con el legacy para coexistencia CLI.
/// Soporta matching substring contra URL/host y patrones glob con `*`.
@available(macOS 14, *)
@Observable
@MainActor
public final class StatusOverridesStore {
    /// Lista actual de overrides.
    public private(set) var overrides: [StatusOverride] = []

    private let storagePath: String
    private let bus: EventBus

    /// - Parameters:
    ///   - storagePath: archivo donde persistir los overrides (formato `pattern\tstatus`).
    ///     `AppCore` pasa el path canónico; los tests inyectan temp dirs.
    ///   - bus: bus de eventos al que publicar `StatusOverridesChangedEvent` tras mutaciones.
    public init(storagePath: String, bus: EventBus) {
        self.storagePath = storagePath
        self.bus = bus
        reload()
    }

    // MARK: - Actions

    /// Agrega un override. Trim automático. No-op si el pattern está vacío.
    /// Si ya existe un override con el mismo pattern, lo reemplaza con el nuevo status.
    public func add(pattern: String, status: Int) {
        let sanitized = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return }
        if let idx = overrides.firstIndex(where: { $0.pattern == sanitized }) {
            // Dedup: mismo pattern reemplaza status.
            guard overrides[idx].status != status else { return }
            overrides[idx] = StatusOverride(pattern: sanitized, status: status)
        } else {
            overrides.append(StatusOverride(pattern: sanitized, status: status))
        }
        persist()
        publishChange()
    }

    /// Quita el override con el pattern dado. No-op si no existe.
    public func remove(pattern: String) {
        let sanitized = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = overrides.count
        overrides.removeAll { $0.pattern == sanitized }
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

    private func publishChange() {
        let snapshot = overrides.map { ($0.pattern, $0.status) }
        let bus = self.bus
        Task { await bus.publish(StatusOverridesChangedEvent(overrides: snapshot)) }
    }

    // MARK: - Matching

    /// Retorna el status code si alguna regla matchea `url` o `host`.
    ///
    /// Reglas (replican el comportamiento del legacy `StatusOverrideStore.match`):
    /// 1. Substring case-insensitive: si el pattern aparece en el URL o el host.
    /// 2. Glob con `*`: se compila como regex y se matchea contra el URL completo.
    ///
    /// Retorna `nil` si ningún override aplica.
    public func match(url: String, host: String) -> Int? {
        let lowerURL = url.lowercased()
        let lowerHost = host.lowercased()
        for override in overrides {
            let lowerPattern = override.pattern.lowercased()
            // Substring match contra URL o host.
            if lowerURL.contains(lowerPattern) || lowerHost.contains(lowerPattern) {
                return override.status
            }
            // Glob con `*` → regex anclado.
            if override.pattern.contains("*") {
                let escaped = NSRegularExpression.escapedPattern(for: override.pattern)
                let regexString = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"
                if let re = try? NSRegularExpression(pattern: regexString, options: [.caseInsensitive]),
                   re.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil {
                    return override.status
                }
            }
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
                guard parts.count == 2, let status = Int(parts[1]) else { return nil }
                return StatusOverride(pattern: String(parts[0]), status: status)
            }
    }

    private func persist() {
        let content = overrides.map { "\($0.pattern)\t\($0.status)" }.joined(separator: "\n")
        let toWrite = overrides.isEmpty ? "" : content + "\n"
        try? toWrite.write(toFile: storagePath, atomically: true, encoding: .utf8)
    }
}

import Foundation
import Observation
import PryLib

/// Representa una regla Map Local: un patrón regex que matchea contra la URL
/// entrante y un path de archivo local cuyo contenido se devuelve como respuesta.
///
/// Se persiste en formato `pattern\tfilePath` por línea, compatible con el legacy
/// `MapLocal` (PryLib) — ambos leen y escriben el mismo archivo cuando
/// `AppCore` inyecta `StoragePaths.mapsFile`.
public struct MapLocalMapping: Sendable, Equatable {
    public let pattern: String
    public let filePath: String

    public init(pattern: String, filePath: String) {
        self.pattern = pattern
        self.filePath = filePath
    }
}

/// Store de mappings Map Local. Reemplaza progresivamente a `MapLocal`
/// (PryLib legacy) en el contexto de PryApp.
///
/// Persiste a un archivo configurable (`AppCore.mapsStoragePath`). Formato:
/// `pattern\tfilePath` por línea, compatible con el legacy para coexistencia CLI.
/// `match(url:)` retorna el path del archivo mapeado (no el contenido) — la
/// lectura real la hace el interceptor, que también infiere Content-Type.
@available(macOS 14, *)
@Observable
@MainActor
public final class MapLocalStore {
    /// Lista actual de mappings.
    public private(set) var mappings: [MapLocalMapping] = []

    private let storagePath: String
    private let bus: EventBus

    /// - Parameters:
    ///   - storagePath: archivo donde persistir los mappings (formato `pattern\tfilePath`).
    ///     `AppCore` pasa el path canónico; los tests inyectan temp dirs.
    ///   - bus: bus de eventos al que publicar `MapLocalChangedEvent` tras mutaciones.
    public init(storagePath: String, bus: EventBus) {
        self.storagePath = storagePath
        self.bus = bus
        reload()
    }

    // MARK: - Actions

    /// Agrega un mapping. Trim automático del pattern. No-op si el pattern o el
    /// filePath están vacíos. Si ya existe un mapping con el mismo pattern, lo
    /// reemplaza con el nuevo filePath.
    public func add(pattern: String, filePath: String) {
        let sanitizedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedPath = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedPattern.isEmpty, !sanitizedPath.isEmpty else { return }
        if let idx = mappings.firstIndex(where: { $0.pattern == sanitizedPattern }) {
            guard mappings[idx].filePath != sanitizedPath else { return }
            mappings[idx] = MapLocalMapping(pattern: sanitizedPattern, filePath: sanitizedPath)
        } else {
            mappings.append(MapLocalMapping(pattern: sanitizedPattern, filePath: sanitizedPath))
        }
        persist()
        publishChange()
    }

    /// Quita el mapping con el pattern dado. No-op si no existe.
    public func remove(pattern: String) {
        let sanitized = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = mappings.count
        mappings.removeAll { $0.pattern == sanitized }
        if mappings.count != before {
            persist()
            publishChange()
        }
    }

    /// Vacía la lista completa.
    public func clear() {
        guard !mappings.isEmpty else { return }
        mappings.removeAll()
        persist()
        publishChange()
    }

    private func publishChange() {
        let snapshot = mappings.map { ($0.pattern, $0.filePath) }
        let bus = self.bus
        Task { await bus.publish(MapLocalChangedEvent(mappings: snapshot)) }
    }

    // MARK: - Matching

    /// Retorna el filePath asociado al primer mapping cuyo pattern matchea `url`.
    ///
    /// Reglas (replican el comportamiento del legacy `MapLocal.match`):
    /// 1. El pattern se compila como `NSRegularExpression` y se aplica al URL completo.
    /// 2. Si la compilación falla, ese mapping se ignora.
    ///
    /// Retorna `nil` si ningún mapping aplica.
    public func match(url: String) -> String? {
        for mapping in mappings {
            guard let regex = try? NSRegularExpression(pattern: mapping.pattern) else { continue }
            let range = NSRange(url.startIndex..., in: url)
            if regex.firstMatch(in: url, range: range) != nil {
                return mapping.filePath
            }
        }
        return nil
    }

    // MARK: - Persistence

    private func reload() {
        guard let content = try? String(contentsOfFile: storagePath, encoding: .utf8) else {
            mappings = []
            return
        }
        mappings = content
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                let pattern = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let path = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pattern.isEmpty, !path.isEmpty else { return nil }
                return MapLocalMapping(pattern: pattern, filePath: path)
            }
    }

    private func persist() {
        let content = mappings.map { "\($0.pattern)\t\($0.filePath)" }.joined(separator: "\n")
        let toWrite = mappings.isEmpty ? "" : content + "\n"
        try? toWrite.write(toFile: storagePath, atomically: true, encoding: .utf8)
    }
}

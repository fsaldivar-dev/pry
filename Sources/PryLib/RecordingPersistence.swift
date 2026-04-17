import Foundation

/// Persistencia pura de `Recording` a `~/.pry/recordings/`. Sin singletons.
///
/// Extraído de `Recorder` (legacy) para permitir que `RecordingsStore` de la
/// nueva arquitectura owne su state sin wrappear `Recorder.shared`.
///
/// Formato: JSON pretty-printed con fechas ISO8601, 1 archivo por recording.
/// Compatible con lo que escribe/lee el legacy `Recorder` → CLI y GUI ven
/// las mismas grabaciones.
public enum RecordingPersistence {

    private static var dir: String {
        StoragePaths.ensureRoot()
        return StoragePaths.recordingsDir
    }

    /// Sanitiza el nombre para evitar path traversal. Rechaza separadores de
    /// path + componentes `..` + nombres vacíos. Retorna nil si el nombre
    /// no es seguro.
    private static func sanitize(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.contains("/"), !trimmed.contains("\\"),
              !trimmed.contains(".."), trimmed != "." else { return nil }
        return trimmed
    }

    /// Guarda un `Recording` a `~/.pry/recordings/<name>.json`.
    public static func save(_ recording: Recording) throws {
        guard let name = sanitize(recording.name) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(recording)
        let path = "\(dir)/\(name).json"
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// Carga un `Recording` por nombre. Retorna nil si el nombre es inseguro,
    /// el archivo no existe, o el JSON es inválido.
    public static func load(name: String) -> Recording? {
        guard let safe = sanitize(name) else { return nil }
        let path = "\(dir)/\(safe).json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Recording.self, from: data)
    }

    /// Lista los nombres de todos los recordings guardados (sin extensión).
    public static func list() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return files.filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
    }

    /// Elimina un recording. No-op si el nombre es inseguro o no existe.
    public static func delete(name: String) {
        guard let safe = sanitize(name) else { return }
        let path = "\(dir)/\(safe).json"
        try? FileManager.default.removeItem(atPath: path)
    }
}

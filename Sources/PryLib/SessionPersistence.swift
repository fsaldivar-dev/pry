import Foundation

/// Request/response persistido para "Session Persistence" (issue #91).
///
/// Shape dedicado — no atado a `RequestStore.CapturedRequest` (legacy) ni a
/// los eventos del bus. Contiene los datos mínimos útiles para inspección
/// post-reinicio.
public struct PersistedSessionRequest: Codable, Sendable, Equatable {
    public let requestID: Int
    public let capturedAt: Date
    public let method: String
    public let host: String
    public let url: String
    public let requestHeaders: [[String]]    // pares [name, value]
    public let requestBody: String?
    public let statusCode: UInt
    public let responseHeaders: [[String]]
    public let responseBody: String?
    public let latencyMs: Int

    public init(
        requestID: Int, capturedAt: Date, method: String, host: String, url: String,
        requestHeaders: [(String, String)], requestBody: String?,
        statusCode: UInt, responseHeaders: [(String, String)], responseBody: String?,
        latencyMs: Int
    ) {
        self.requestID = requestID
        self.capturedAt = capturedAt
        self.method = method
        self.host = host
        self.url = url
        self.requestHeaders = requestHeaders.map { [$0.0, $0.1] }
        self.requestBody = requestBody
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders.map { [$0.0, $0.1] }
        self.responseBody = responseBody
        self.latencyMs = latencyMs
    }
}

/// Persistencia de sesión a `~/.pry/sessions/last.jsonl` (newline-delimited JSON).
///
/// Diseño:
/// - JSONL (una request por línea) habilita append O(1) sin reescribir todo el file.
/// - Caps: entries (default 5000) o bytes (default 50 MB) — drop-oldest mediante
///   rewrite cuando se excede.
/// - Opt-in vía `isEnabled` (UserDefaults, default false por privacidad).
/// - Sin singletons — todos los métodos son `static`, state vive en UserDefaults + disco.
public enum SessionPersistence {
    public static let maxEntries: Int = 5000
    public static let maxBytes: Int = 50 * 1024 * 1024

    private static let enabledKey = "pry.session.persistEnabled"

    /// Override para tests — cuando non-nil, todas las operaciones usan este path.
    nonisolated(unsafe) public static var overridePath: String?

    private static var path: String {
        overridePath ?? StoragePaths.sessionFile
    }

    // MARK: - Enablement (UserDefaults)

    public static func isEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    public static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }

    // MARK: - Append + Load + Clear

    /// Append una request a la sesión persistida. Si excede los caps, hace
    /// prune (reescribe el file con sólo las últimas N entradas).
    ///
    /// No-op si `isEnabled() == false` (check en el caller; acá asumimos ya
    /// pasó por ahí).
    @discardableResult
    public static func append(_ request: PersistedSessionRequest) -> Bool {
        ensureDir()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let line = try? encoder.encode(request),
              let lineStr = String(data: line, encoding: .utf8) else { return false }
        let entry = lineStr + "\n"
        guard let data = entry.data(using: .utf8) else { return false }

        // Append atómico.
        if FileManager.default.fileExists(atPath: path) {
            if let handle = FileHandle(forWritingAtPath: path) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }

        // Chequeo ocasional de caps (no en cada append — costoso). Cada 100
        // entries aproximado, hacer prune.
        if Int.random(in: 0..<100) == 0 {
            pruneIfNeeded()
        }
        return true
    }

    /// Carga todas las requests persistidas. Silencia errores de decode de
    /// líneas individuales (tolerante a corruption parcial).
    public static func load() -> [PersistedSessionRequest] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return content.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(PersistedSessionRequest.self, from: data)
        }
    }

    /// Elimina el archivo de sesión.
    public static func clear() {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Tamaño del file en bytes (0 si no existe).
    public static func currentSizeBytes() -> Int {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
    }

    /// Cantidad de requests persistidas (conteo de líneas non-empty).
    public static func currentCount() -> Int {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return 0
        }
        return content.split(separator: "\n").count
    }

    // MARK: - Prune

    /// Chequea los caps y rewrite si excede. Keeps tail de `maxEntries` y
    /// después trimmea por `maxBytes` si hiciera falta.
    public static func pruneIfNeeded() {
        let bytes = currentSizeBytes()
        let count = currentCount()
        guard count > maxEntries || bytes > maxBytes else { return }

        var entries = load()
        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // Reconstruir con posible drop adicional por bytes.
        var rebuilt = buildJSONL(entries, encoder: encoder)
        while rebuilt.count > maxBytes, entries.count > 1 {
            let drop = max(1, entries.count / 10)
            entries = Array(entries.suffix(entries.count - drop))
            rebuilt = buildJSONL(entries, encoder: encoder)
        }
        try? rebuilt.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func buildJSONL(_ entries: [PersistedSessionRequest], encoder: JSONEncoder) -> Data {
        var result = Data()
        for e in entries {
            guard let line = try? encoder.encode(e) else { continue }
            result.append(line)
            result.append(contentsOf: [0x0A]) // \n
        }
        return result
    }

    private static func ensureDir() {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
}

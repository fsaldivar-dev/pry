import Foundation

// MARK: - Recording Data Model

public struct CodableHeader: Codable, Equatable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name; self.value = value
    }
}

public struct RecordingStep: Codable, Equatable {
    public let sequence: Int
    public let timestamp: Date
    public let method: String
    public let url: String
    public let host: String
    public let requestHeaders: [CodableHeader]
    public let requestBody: String?
    public let statusCode: UInt?
    public let responseHeaders: [CodableHeader]
    public let responseBody: String?
    public let latencyMs: Int

    public init(sequence: Int, timestamp: Date, method: String, url: String, host: String,
                requestHeaders: [CodableHeader], requestBody: String?,
                statusCode: UInt?, responseHeaders: [CodableHeader], responseBody: String?,
                latencyMs: Int) {
        self.sequence = sequence; self.timestamp = timestamp
        self.method = method; self.url = url; self.host = host
        self.requestHeaders = requestHeaders; self.requestBody = requestBody
        self.statusCode = statusCode; self.responseHeaders = responseHeaders
        self.responseBody = responseBody; self.latencyMs = latencyMs
    }
}

public struct Recording: Codable, Equatable {
    public let name: String
    public let startedAt: Date
    public var stoppedAt: Date?
    public var steps: [RecordingStep]

    public init(name: String) {
        self.name = name
        self.startedAt = Date()
        self.stoppedAt = nil
        self.steps = []
    }
}

// MARK: - Recorder

/// Records proxy traffic as ordered sequences for replay, mock generation, and diffing.
/// Recordings are stored as JSON in .pry/recordings/.
public final class Recorder {

    public static let shared = Recorder()

    private static var recordingsDir: String {
        StoragePaths.ensureRoot()
        return StoragePaths.recordingsDir
    }

    private var currentRecording: Recording?
    private var pendingRequests: [Int: (start: Date, method: String, url: String, host: String, headers: [CodableHeader], body: String?)] = [:]
    private let queue = DispatchQueue(label: "dev.pry.recorder")

    /// Domains to filter during recording. Empty = record all traffic.
    private var filterDomains: [String] = []

    private init() {}

    /// Whether recording is currently active.
    public var isRecording: Bool {
        queue.sync { currentRecording != nil && currentRecording?.stoppedAt == nil }
    }

    /// Start a new recording, optionally filtering by domains.
    public func start(name: String, domains: [String] = []) {
        queue.sync {
            currentRecording = Recording(name: name)
            pendingRequests = [:]
            filterDomains = domains.map { $0.lowercased() }
        }
    }

    /// Stop the current recording and save to disk.
    public func stop() -> Recording? {
        queue.sync {
            guard var recording = currentRecording else { return nil }
            recording.stoppedAt = Date()
            currentRecording = recording
            try? Self.saveRecording(recording)
            let result = recording
            currentRecording = nil
            pendingRequests = [:]
            return result
        }
    }

    /// Note that a request has started (called from HTTPInterceptor).
    public func noteRequestStart(requestId: Int, method: String, url: String, host: String,
                                  headers: [(String, String)], body: String?) {
        queue.sync {
            guard currentRecording != nil else { return }
            // Filter by domains if configured
            if !filterDomains.isEmpty {
                let h = host.lowercased()
                let matches = filterDomains.contains { d in
                    h == d || h.hasSuffix(".\(d)")
                }
                guard matches else { return }
            }
            pendingRequests[requestId] = (
                start: Date(),
                method: method,
                url: url,
                host: host,
                headers: headers.map { CodableHeader(name: $0.0, value: $0.1) },
                body: body
            )
        }
    }

    /// Note that a response has completed (called from response path).
    public func noteResponseComplete(requestId: Int, statusCode: UInt,
                                      headers: [(String, String)], body: String?) {
        queue.sync {
            guard var recording = currentRecording,
                  let pending = pendingRequests.removeValue(forKey: requestId) else { return }

            let latency = Int(Date().timeIntervalSince(pending.start) * 1000)
            let step = RecordingStep(
                sequence: recording.steps.count + 1,
                timestamp: pending.start,
                method: pending.method,
                url: pending.url,
                host: pending.host,
                requestHeaders: pending.headers,
                requestBody: pending.body,
                statusCode: statusCode,
                responseHeaders: headers.map { CodableHeader(name: $0.0, value: $0.1) },
                responseBody: body,
                latencyMs: latency
            )
            recording.steps.append(step)
            currentRecording = recording
        }
    }

    // MARK: - Persistence

    /// Save a recording to disk.
    private static func saveRecording(_ recording: Recording) throws {
        try FileManager.default.createDirectory(atPath: recordingsDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(recording)
        let path = "\(recordingsDir)/\(recording.name).json"
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// Load a recording by name.
    public static func load(name: String) -> Recording? {
        let path = "\(recordingsDir)/\(name).json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Recording.self, from: data)
    }

    /// List all recording names.
    public static func list() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: recordingsDir) else { return [] }
        return files.filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
            .sorted()
    }

    /// Delete a recording.
    public static func delete(name: String) {
        let path = "\(recordingsDir)/\(name).json"
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Clear all recordings.
    public static func clearAll() {
        try? FileManager.default.removeItem(atPath: recordingsDir)
    }

    /// Convert a recording to loose mocks via MockEngine.
    public static func toMocks(name: String) -> Int {
        guard let recording = load(name: name) else { return 0 }
        var count = 0
        for step in recording.steps {
            if let body = step.responseBody {
                // Extract path from URL (head.uri can be full URL for HTTP)
                var pattern = step.url
                if pattern.hasPrefix("http://") || pattern.hasPrefix("https://") {
                    if let url = URL(string: pattern) {
                        pattern = url.path.isEmpty ? "/" : url.path
                    }
                }
                let mock = UnifiedMock(
                    method: step.method,
                    pattern: pattern,
                    host: step.host,
                    status: step.statusCode ?? 200,
                    body: body,
                    source: .recording(name: name),
                    isEnabled: true
                )
                MockEngine.shared.addLooseMock(mock)
                count += 1
            }
        }
        return count
    }
}

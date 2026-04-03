import Foundation

struct Config {
    static let configFile = ".pryconfig"
    static let logFile = "/tmp/pry.log"
    static let pidFile = "/tmp/pry.pid"
    static let mockFile = "/tmp/pry.mocks"
    static let defaultPort = 8080

    static func readAll() -> [String: String] {
        guard let content = try? String(contentsOfFile: configFile, encoding: .utf8) else {
            return [:]
        }
        var result: [String: String] = [:]
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if let eq = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                result[key] = value
            }
        }
        return result
    }

    static func get(_ key: String) -> String? {
        readAll()[key]
    }

    static func set(_ key: String, value: String) {
        var config = readAll()
        config[key] = value
        let content = config.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        try? content.write(toFile: configFile, atomically: true, encoding: .utf8)
    }

    static func port() -> Int {
        if let portStr = get("port"), let port = Int(portStr) {
            return port
        }
        return defaultPort
    }

    static func appendLog(_ entry: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(entry)\n"
        if let handle = FileHandle(forWritingAtPath: logFile) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(toFile: logFile, atomically: true, encoding: .utf8)
        }
    }

    static func readLog(last n: Int = 50) -> [String] {
        guard let content = try? String(contentsOfFile: logFile, encoding: .utf8) else {
            return []
        }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        return Array(lines.suffix(n))
    }

    static func clearLog() {
        try? "".write(toFile: logFile, atomically: true, encoding: .utf8)
    }

    static func saveMock(path: String, response: String) {
        let entry = "\(path)\t\(response)\n"
        if let handle = FileHandle(forWritingAtPath: mockFile) {
            handle.seekToEndOfFile()
            handle.write(entry.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? entry.write(toFile: mockFile, atomically: true, encoding: .utf8)
        }
    }

    static func loadMocks() -> [String: String] {
        guard let content = try? String(contentsOfFile: mockFile, encoding: .utf8) else {
            return [:]
        }
        var mocks: [String: String] = [:]
        for line in content.components(separatedBy: "\n") {
            if line.isEmpty { continue }
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 2 {
                mocks[parts[0]] = parts[1]
            }
        }
        return mocks
    }

    static func clearMocks() {
        try? "".write(toFile: mockFile, atomically: true, encoding: .utf8)
    }
}

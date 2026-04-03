import Foundation

enum ProxyError: Error, CustomStringConvertible {
    case alreadyRunning
    case notRunning
    case invalidPort(String)
    case mockFileNotFound(String)
    case invalidJSON(String)
    case connectionFailed(String)

    public var description: String {
        switch self {
        case .alreadyRunning:
            return "Proxy is already running"
        case .notRunning:
            return "Proxy is not running"
        case .invalidPort(let port):
            return "Invalid port: \(port)"
        case .mockFileNotFound(let path):
            return "Mock file not found: \(path)"
        case .invalidJSON(let reason):
            return "Invalid JSON: \(reason)"
        case .connectionFailed(let host):
            return "Connection failed: \(host)"
        }
    }
}

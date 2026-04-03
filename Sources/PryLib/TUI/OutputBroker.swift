import Foundation

/// Thread-safe output broker. All proxy handlers write here instead of print().
/// In TUI mode, the TUI reads from the buffer. In headless mode, it prints directly.
public class OutputBroker {
    public static let shared = OutputBroker()

    private let queue = DispatchQueue(label: "pry.output", qos: .userInteractive)
    private var entries: [LogEntry] = []
    private var headless = true
    private var maxEntries = 500
    private var onNewEntry: ((LogEntry) -> Void)?

    public struct LogEntry {
        public let timestamp: Date
        public let text: String
        public let colored: String
        public let type: EntryType
    }

    public enum EntryType {
        case request
        case response
        case mock
        case tunnel
        case intercept
        case error
        case info
    }

    public func setTUIMode(callback: @escaping (LogEntry) -> Void) {
        queue.sync {
            headless = false
            onNewEntry = callback
        }
    }

    public func setHeadlessMode() {
        queue.sync {
            headless = true
            onNewEntry = nil
        }
    }

    public func log(_ colored: String, plain: String? = nil, type: EntryType = .info) {
        let entry = LogEntry(
            timestamp: Date(),
            text: plain ?? stripANSI(colored),
            colored: colored,
            type: type
        )

        queue.async {
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }

            if self.headless {
                // Direct print like before
                print(entry.colored)
            } else {
                self.onNewEntry?(entry)
            }
        }

        // Also append to file log
        Config.appendLog(entry.text)
    }

    func getEntries(last n: Int? = nil) -> [LogEntry] {
        queue.sync {
            if let n = n {
                return Array(entries.suffix(n))
            }
            return entries
        }
    }

    func clear() {
        queue.sync {
            entries.removeAll()
        }
    }

    private func stripANSI(_ text: String) -> String {
        // Remove ANSI escape sequences
        text.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
    }
}

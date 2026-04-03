import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

class TUI {
    private let terminal = Terminal()
    private let broker = OutputBroker.shared
    private let store = RequestStore.shared
    private var running = true
    private var rows: Int = 24
    private var cols: Int = 80

    // Navigation
    private var selectedIndex: Int = 0
    private var listScrollOffset: Int = 0
    private var showMocks = false

    // Command line
    private var commandBuffer: String = ""
    private var commandHistory: [String] = []

    // Layout
    private let port: Int
    private var needsFullRedraw = true
    private var needsListRedraw = true
    private var needsDetailRedraw = true

    // Dirty flag from store updates
    private var storeChanged = false

    var onCommand: ((String) -> Void)?

    init(port: Int) {
        self.port = port
    }

    func start() {
        let size = ANSI.getSize()
        rows = size.rows
        cols = size.cols

        terminal.enableRawMode()
        ANSI.write(ANSI.enterAltBuffer + ANSI.hideCursor + ANSI.clearScreen)

        // Register for traffic updates
        broker.setTUIMode { [weak self] _ in
            // OutputBroker still logs — we just don't use it for display
        }

        store.onChange = { [weak self] in
            self?.storeChanged = true
        }

        renderSplash()
        runLoop()
        cleanup()
    }

    func stop() { running = false }

    private func cleanup() {
        broker.setHeadlessMode()
        store.onChange = nil
        terminal.disableRawMode()
        ANSI.write(ANSI.showCursor + ANSI.exitAltBuffer)
    }

    // MARK: - Splash Screen

    private func renderSplash() {
        let cat = [
            "    ╱|、",
            "   (˚ˎ 。7",
            "    |、˜〵",
            "    じしˍ,)ノ     ╭──────────────────╮",
            "   ·····•·····    │  p r y  v0.2     │",
            "                  │  proxy for devs  │",
            "                  ╰──────────────────╯",
        ]

        let startRow = max(1, (rows - cat.count) / 2 - 2)
        var buf = ANSI.clearScreen

        for (i, line) in cat.enumerated() {
            let col = max(1, (cols - 42) / 2)
            buf += ANSI.moveTo(row: startRow + i, col: col) + ANSI.fgCyan + line + ANSI.reset
        }

        // Subtitle
        let subRow = startRow + cat.count + 2
        let subtitle = "Listening on :\(port) · Press any key to continue"
        let subCol = max(1, (cols - subtitle.count) / 2)
        buf += ANSI.moveTo(row: subRow, col: subCol) + ANSI.dim + subtitle + ANSI.reset

        ANSI.write(buf)

        // Wait for any key or first request
        while running {
            if let _ = terminal.readKey() { break }
            if store.count() > 0 { break }
        }
    }

    // MARK: - Run Loop

    private func runLoop() {
        renderFull()
        while running {
            let newSize = ANSI.getSize()
            if newSize.rows != rows || newSize.cols != cols {
                rows = newSize.rows
                cols = newSize.cols
                needsFullRedraw = true
            }

            if let key = terminal.readKey() {
                handleKey(key)
            }

            if storeChanged {
                storeChanged = false
                // Auto-select latest
                let count = store.count()
                if count > 0 && selectedIndex == count - 2 {
                    selectedIndex = count - 1
                }
                needsListRedraw = true
                needsDetailRedraw = true
            }

            if needsFullRedraw {
                renderFull()
                needsFullRedraw = false
                needsListRedraw = false
                needsDetailRedraw = false
            } else {
                if needsListRedraw {
                    renderList()
                    needsListRedraw = false
                }
                if needsDetailRedraw {
                    renderDetail()
                    needsDetailRedraw = false
                }
            }
        }
    }

    // MARK: - Input

    private func handleKey(_ key: KeyEvent) {
        switch key {
        case .ctrlC, .ctrlD:
            running = false

        case .up:
            if selectedIndex > 0 {
                selectedIndex -= 1
                needsListRedraw = true
                needsDetailRedraw = true
            }

        case .down:
            let count = store.count()
            if selectedIndex < count - 1 {
                selectedIndex += 1
                needsListRedraw = true
                needsDetailRedraw = true
            }

        case .tab:
            showMocks = !showMocks
            needsDetailRedraw = true

        case .enter:
            if !commandBuffer.isEmpty {
                let cmd = commandBuffer
                commandHistory.append(cmd)
                commandBuffer = ""
                renderCommandLine()
                onCommand?(cmd)
            }

        case .backspace:
            if !commandBuffer.isEmpty {
                commandBuffer.removeLast()
                renderCommandLine()
            }

        case .char(let c):
            if commandBuffer.isEmpty && c == "q" {
                running = false
                return
            }
            commandBuffer.append(c)
            renderCommandLine()

        case .escape:
            if !commandBuffer.isEmpty {
                commandBuffer = ""
                renderCommandLine()
            }

        default:
            break
        }
    }

    // MARK: - Layout Geometry

    private var listWidth: Int { max(cols / 3, 25) }
    private var detailWidth: Int { cols - listWidth - 1 } // -1 for border
    private var contentHeight: Int { max(rows - 3, 4) } // -1 status, -1 separator, -1 cmdline
    private var detailSplitRow: Int { 1 + 1 + contentHeight / 2 } // after status + half content

    // MARK: - Full Render

    private func renderFull() {
        var buf = ANSI.clearScreen

        // Status bar (row 1)
        buf += renderStatusBar()

        // Content area: list (left) + detail (right)
        let requests = store.getAll()
        buf += renderListContent(requests)
        buf += renderDetailContent(requests)

        // Vertical border between list and detail
        for r in 2...contentHeight + 1 {
            buf += ANSI.moveTo(row: r, col: listWidth + 1) + ANSI.dim + "│" + ANSI.reset
        }

        // Bottom separator
        buf += ANSI.moveTo(row: rows - 1, col: 1) + ANSI.dim + String(repeating: "─", count: cols) + ANSI.reset

        // Command line
        buf += renderCommandLineStr()

        ANSI.write(buf)
    }

    // MARK: - Status Bar

    private func renderStatusBar() -> String {
        let watchlist = Watchlist.load()
        let mocks = Config.loadMocks()
        let count = store.count()
        let status = " 🐱 :\(port) │ \(watchlist.count) domains │ \(mocks.count) mocks │ \(count) requests │ ↑↓ nav │ [Tab] mocks │ q quit "
        let padded = status.padding(toLength: cols, withPad: " ", startingAt: 0)
        return ANSI.moveTo(row: 1, col: 1) + ANSI.inverse + padded + ANSI.reset
    }

    // MARK: - Request List (Left Panel)

    private func renderList() {
        let requests = store.getAll()
        ANSI.write(renderListContent(requests))
    }

    private func renderListContent(_ requests: [RequestStore.CapturedRequest]) -> String {
        var buf = ""
        let height = contentHeight

        // Adjust scroll to keep selected visible
        if selectedIndex < listScrollOffset {
            listScrollOffset = selectedIndex
        }
        if selectedIndex >= listScrollOffset + height {
            listScrollOffset = selectedIndex - height + 1
        }

        for i in 0..<height {
            let row = 2 + i
            let idx = listScrollOffset + i
            buf += ANSI.moveTo(row: row, col: 1)

            if idx < requests.count {
                let req = requests[idx]
                let isSelected = idx == selectedIndex
                let prefix = isSelected ? "►" : " "

                // Color by type
                let methodColor: String
                if req.isMock {
                    methodColor = ANSI.fgYellow
                } else if req.isTunnel {
                    methodColor = ANSI.fgGray
                } else if let code = req.statusCode, code >= 400 {
                    methodColor = ANSI.fgRed
                } else {
                    methodColor = ANSI.fgGreen
                }

                let status = req.statusCode.map { "\($0)" } ?? "..."
                let line = "\(prefix) \(req.appIcon) \(req.method) \(status) \(req.host)"
                let truncated = String(line.prefix(listWidth - 1))
                let padded = truncated.padding(toLength: listWidth - 1, withPad: " ", startingAt: 0)

                if isSelected {
                    buf += ANSI.inverse + methodColor + padded + ANSI.reset
                } else {
                    buf += methodColor + padded + ANSI.reset
                }
            } else {
                buf += String(repeating: " ", count: listWidth - 1)
            }
        }
        return buf
    }

    // MARK: - Detail Panel (Right)

    private func renderDetail() {
        let requests = store.getAll()
        ANSI.write(renderDetailContent(requests))
    }

    private func renderDetailContent(_ requests: [RequestStore.CapturedRequest]) -> String {
        var buf = ""
        let startCol = listWidth + 2
        let width = detailWidth - 1
        let height = contentHeight

        if showMocks {
            return renderMocksView(startCol: startCol, width: width, height: height)
        }

        guard selectedIndex < requests.count else {
            // Empty state
            for i in 0..<height {
                buf += ANSI.moveTo(row: 2 + i, col: startCol) + String(repeating: " ", count: width)
            }
            buf += ANSI.moveTo(row: 2 + height / 2, col: startCol)
            buf += ANSI.dim + "No request selected" + ANSI.reset
            return buf
        }

        let req = requests[selectedIndex]
        let halfHeight = height / 2
        var line = 0

        // Request section header
        buf += writeLine(row: 2, col: startCol, width: width, text: ANSI.bold + ANSI.fgGreen + " Request" + ANSI.reset)
        line += 1

        // Request info
        buf += writeLine(row: 2 + line, col: startCol, width: width, text: " \(req.method) \(req.url)")
        line += 1
        buf += writeLine(row: 2 + line, col: startCol, width: width, text: ANSI.dim + " Host: \(req.host)" + ANSI.reset)
        line += 1
        buf += writeLine(row: 2 + line, col: startCol, width: width, text: ANSI.dim + " App: \(req.appIcon) \(req.appName)" + ANSI.reset)
        line += 1

        // Request headers
        for (name, value) in req.requestHeaders.prefix(4) {
            if line >= halfHeight { break }
            buf += writeLine(row: 2 + line, col: startCol, width: width, text: ANSI.dim + " \(name): \(value)" + ANSI.reset)
            line += 1
        }

        // Request body
        if let body = req.requestBody, !body.isEmpty, line < halfHeight {
            buf += writeLine(row: 2 + line, col: startCol, width: width, text: ANSI.dim + " Body: \(body.prefix(width - 7))" + ANSI.reset)
            line += 1
        }

        // Clear remaining request lines
        while line < halfHeight {
            buf += writeLine(row: 2 + line, col: startCol, width: width, text: "")
            line += 1
        }

        // Separator
        buf += ANSI.moveTo(row: 2 + halfHeight, col: startCol)
        buf += ANSI.dim + String(repeating: "─", count: width) + ANSI.reset

        // Response section
        line = halfHeight + 1

        if req.isTunnel {
            buf += writeLine(row: 2 + line, col: startCol, width: width, text: ANSI.fgGray + " 🔒 Tunnel (encrypted passthrough)" + ANSI.reset)
            line += 1
        } else if let code = req.statusCode {
            let statusColor = code < 400 ? ANSI.fgCyan : ANSI.fgRed
            let mockTag = req.isMock ? ANSI.fgYellow + " MOCK" + ANSI.reset : ""
            buf += writeLine(row: 2 + line, col: startCol, width: width, text: ANSI.bold + statusColor + " Response \(code)" + ANSI.reset + mockTag)
            line += 1

            // Response headers
            for (name, value) in req.responseHeaders.prefix(4) {
                if line >= height { break }
                buf += writeLine(row: 2 + line, col: startCol, width: width, text: ANSI.dim + " \(name): \(value)" + ANSI.reset)
                line += 1
            }

            // Response body
            if let body = req.responseBody, !body.isEmpty {
                let bodyLines = body.split(separator: "\n", omittingEmptySubsequences: false)
                for bodyLine in bodyLines.prefix(height - line) {
                    if line >= height { break }
                    buf += writeLine(row: 2 + line, col: startCol, width: width, text: " \(bodyLine)")
                    line += 1
                }
            }
        } else {
            buf += writeLine(row: 2 + line, col: startCol, width: width, text: ANSI.dim + " Waiting for response..." + ANSI.reset)
            line += 1
        }

        // Clear remaining
        while line < height {
            buf += writeLine(row: 2 + line, col: startCol, width: width, text: "")
            line += 1
        }

        return buf
    }

    // MARK: - Mocks View

    private func renderMocksView(startCol: Int, width: Int, height: Int) -> String {
        var buf = ""
        let mocks = Config.loadMocks()

        buf += writeLine(row: 2, col: startCol, width: width, text: ANSI.bold + ANSI.fgYellow + " Active Mocks" + ANSI.reset)

        if mocks.isEmpty {
            buf += writeLine(row: 3, col: startCol, width: width, text: ANSI.dim + " No mocks registered" + ANSI.reset)
            for i in 4..<height + 2 {
                buf += writeLine(row: i, col: startCol, width: width, text: "")
            }
        } else {
            var line = 1
            for (path, response) in mocks {
                if line >= height { break }
                buf += writeLine(row: 2 + line, col: startCol, width: width, text: ANSI.fgYellow + " \(path)" + ANSI.reset)
                line += 1
                if line < height {
                    let preview = String(response.prefix(width - 4))
                    buf += writeLine(row: 2 + line, col: startCol, width: width, text: ANSI.dim + "   \(preview)" + ANSI.reset)
                    line += 1
                }
            }
            while line < height {
                buf += writeLine(row: 2 + line, col: startCol, width: width, text: "")
                line += 1
            }
        }

        buf += writeLine(row: 2, col: startCol, width: width, text: ANSI.bold + ANSI.fgYellow + " Active Mocks [Tab to close]" + ANSI.reset)
        return buf
    }

    // MARK: - Command Line

    private func renderCommandLine() {
        ANSI.write(renderCommandLineStr())
    }

    private func renderCommandLineStr() -> String {
        let prompt = "pry> "
        let maxInput = cols - prompt.count - 1
        let displayInput = String(commandBuffer.suffix(maxInput))
        let cursorCol = prompt.count + displayInput.count + 1
        return ANSI.moveTo(row: rows, col: 1) + ANSI.clearLine +
               ANSI.fgCyan + ANSI.bold + prompt + ANSI.reset + displayInput +
               ANSI.showCursor + ANSI.moveTo(row: rows, col: cursorCol)
    }

    // MARK: - Helpers

    private func writeLine(row: Int, col: Int, width: Int, text: String) -> String {
        ANSI.moveTo(row: row, col: col) + ANSI.clearToEnd + String(text.prefix(width))
    }
}

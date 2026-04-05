import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public class TUI {
    private let terminal = Terminal()
    private let broker = OutputBroker.shared
    private let store = RequestStore.shared
    private var running = true
    private var rows: Int = 24
    private var cols: Int = 80

    // Navigation
    private var selectedIndex: Int = 0
    private var codeGenIndex: Int = 0
    private let codeGenFormats = ["curl", "swift", "python"]
    private var listScrollOffset: Int = 0
    private var showMocks = false

    // Command line
    private var commandBuffer: String = ""
    private var commandHistory: [String] = []

    // Filter & Search
    private var activeFilter: String? = nil  // "GET", "POST", "2xx", "4xx", "5xx"
    private var searchQuery: String? = nil
    private var isSearchMode = false
    private var statusMessage: String? = nil
    private let filterCycle = [nil, "GET", "POST", "PUT", "DELETE", "2xx", "4xx", "5xx"] as [String?]
    private var filterIndex = 0

    // Layout
    private let port: Int
    private var needsFullRedraw = true
    private var needsListRedraw = true
    private var needsDetailRedraw = true

    // Dirty flag from store updates
    private var storeChanged = false

    public var onCommand: ((String) -> Void)?

    public init(port: Int) {
        self.port = port
    }

    public func start() {
        let size = ANSI.getSize()
        rows = size.rows
        cols = size.cols

        terminal.enableRawMode()
        // Enter alt buffer, hide cursor, set dark background, fill screen
        var initBuf = ANSI.enterAltBuffer + ANSI.hideCursor + ANSI.bgDark + ANSI.fgWhite
        for r in 1...rows {
            initBuf += ANSI.moveTo(row: r, col: 1) + String(repeating: " ", count: cols)
        }
        ANSI.write(initBuf)

        // Register for traffic updates
        broker.setTUIMode { [weak self] _ in
            // OutputBroker still logs — we just don't use it for display
        }

        store.onChange = { [weak self] in
            self?.storeChanged = true
        }

        defer { cleanup() }
        renderSplash()
        runLoop()
    }

    public func stop() { running = false }

    private func cleanup() {
        broker.setHeadlessMode()
        store.onChange = nil
        terminal.disableRawMode()
        ANSI.write(ANSI.rawReset + ANSI.showCursor + ANSI.exitAltBuffer)
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
        var buf = ANSI.bgDark + ANSI.fgWhite
        for r in 1...rows {
            buf += ANSI.moveTo(row: r, col: 1) + String(repeating: " ", count: cols)
        }

        for (i, line) in cat.enumerated() {
            let col = max(1, (cols - 42) / 2)
            buf += ANSI.moveTo(row: startRow + i, col: col) + ANSI.fgCyanBright + line + ANSI.reset + ANSI.bgDark
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
            if isSearchMode {
                // Apply search and exit search mode
                isSearchMode = false
                commandBuffer = ""
                renderCommandLine()
            } else if !commandBuffer.isEmpty {
                let cmd = commandBuffer
                commandHistory.append(cmd)
                commandBuffer = ""
                renderCommandLine()
                onCommand?(cmd)
            }

        case .backspace:
            if !commandBuffer.isEmpty {
                commandBuffer.removeLast()
                if isSearchMode {
                    if commandBuffer == "/" || commandBuffer.isEmpty {
                        isSearchMode = false
                        searchQuery = nil
                        commandBuffer = ""
                        selectedIndex = 0
                        needsListRedraw = true
                        needsDetailRedraw = true
                    } else {
                        applySearch()
                    }
                }
                renderCommandLine()
            }

        case .char(let c):
            if commandBuffer.isEmpty {
                switch c {
                case "q":
                    running = false
                    return
                case "c":
                    copySelectedAsCurl()
                    return
                case "f":
                    cycleFilter()
                    return
                case "r":
                    repeatSelectedRequest()
                    return
                case "/":
                    isSearchMode = true
                    commandBuffer = "/"
                    renderCommandLine()
                    return
                case "b":
                    resumeSelectedBreakpoint()
                    return
                case "g":
                    cycleCodeGenFormat()
                    return
                case "d":
                    diffWithPrevious()
                    return
                default:
                    break
                }
            }
            commandBuffer.append(c)
            if isSearchMode {
                applySearch()
            }
            renderCommandLine()

        case .escape:
            if isSearchMode {
                isSearchMode = false
                searchQuery = nil
                commandBuffer = ""
                selectedIndex = 0
                needsListRedraw = true
                needsDetailRedraw = true
                renderCommandLine()
            } else if activeFilter != nil {
                activeFilter = nil
                filterIndex = 0
                selectedIndex = 0
                needsListRedraw = true
                needsDetailRedraw = true
                needsFullRedraw = true
            } else if !commandBuffer.isEmpty {
                commandBuffer = ""
                renderCommandLine()
            }

        default:
            break
        }
    }

    // MARK: - Actions

    private func copySelectedAsCurl() {
        let requests = getFilteredRequests()
        guard selectedIndex < requests.count else { return }
        let req = requests[selectedIndex]
        let https = Watchlist.matches(req.host)
        let code: String
        let format = codeGenFormats[codeGenIndex]
        switch format {
        case "swift": code = SwiftGenerator.generate(from: req, https: https)
        case "python": code = PythonGenerator.generate(from: req, https: https)
        default: code = CurlGenerator.generate(from: req, https: https)
        }
        if CurlGenerator.copyToClipboard(code) {
            statusMessage = "✓ Copied as \(format)"
        } else {
            statusMessage = "✗ Copy failed"
        }
        needsFullRedraw = true
        // Clear message after ~2 seconds (checked in run loop)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.statusMessage = nil
            self?.needsFullRedraw = true
        }
    }

    private func repeatSelectedRequest() {
        let requests = getFilteredRequests()
        guard selectedIndex < requests.count else { return }
        let req = requests[selectedIndex]
        guard !req.isTunnel else { return }
        statusMessage = "🔄 Repeating \(req.method) \(req.url)..."
        needsFullRedraw = true
        DispatchQueue.global().async {
            RequestRepeater.repeat_(request: req, proxyPort: self.port)
        }
    }

    private func resumeSelectedBreakpoint() {
        let requests = getFilteredRequests()
        guard selectedIndex < requests.count else { return }
        let req = requests[selectedIndex]

        let manager = RequestBreakpointManager.shared
        let paused = manager.getPaused()
        if let _ = paused.first(where: { $0.id == req.id }) {
            manager.resume(id: req.id, action: .resume)
            statusMessage = "▶ Resumed request \(req.method) \(req.url)"
        } else {
            statusMessage = "No breakpoint on this request"
        }
        needsFullRedraw = true
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.statusMessage = nil
            self?.needsFullRedraw = true
        }
    }

    private func cycleCodeGenFormat() {
        codeGenIndex = (codeGenIndex + 1) % codeGenFormats.count
        statusMessage = "Code gen: \(codeGenFormats[codeGenIndex])"
        needsFullRedraw = true
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.statusMessage = nil
            self?.needsFullRedraw = true
        }
    }

    private func diffWithPrevious() {
        let requests = getFilteredRequests()
        guard selectedIndex > 0, selectedIndex < requests.count else {
            statusMessage = "Select a request (not the first) to diff"
            needsFullRedraw = true
            return
        }
        let req1 = requests[selectedIndex - 1]
        let req2 = requests[selectedIndex]
        let diffLines = DiffTool.diff(req1: req1, req2: req2)
        let formatted = DiffTool.format(diffLines)
        if CurlGenerator.copyToClipboard(formatted) {
            statusMessage = "Diff copied to clipboard"
        } else {
            statusMessage = "Diff copy failed"
        }
        needsFullRedraw = true
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.statusMessage = nil
            self?.needsFullRedraw = true
        }
    }

    private func cycleFilter() {
        filterIndex = (filterIndex + 1) % filterCycle.count
        activeFilter = filterCycle[filterIndex]
        searchQuery = nil
        isSearchMode = false
        selectedIndex = 0
        listScrollOffset = 0
        needsListRedraw = true
        needsDetailRedraw = true
        needsFullRedraw = true
    }

    private func applySearch() {
        let query = String(commandBuffer.dropFirst()) // Remove "/"
        if query.isEmpty {
            searchQuery = nil
        } else {
            searchQuery = query
        }
        selectedIndex = 0
        listScrollOffset = 0
        needsListRedraw = true
        needsDetailRedraw = true
    }

    private func getFilteredRequests() -> [RequestStore.CapturedRequest] {
        var requests = store.getAll()

        if let filter = activeFilter {
            if filter.hasSuffix("xx") {
                // Status code range filter
                let prefix = UInt(String(filter.first!))! * 100
                let range = prefix...(prefix + 99)
                requests = requests.filter { req in
                    guard let code = req.statusCode else { return false }
                    return range.contains(code)
                }
            } else {
                // Method filter
                requests = requests.filter { $0.method.uppercased() == filter }
            }
        }

        if let query = searchQuery, !query.isEmpty {
            requests = requests.filter { req in
                let lower = query.lowercased()
                return req.url.lowercased().contains(lower) ||
                       req.host.lowercased().contains(lower) ||
                       req.method.lowercased().contains(lower)
            }
        }

        return requests
    }

    // MARK: - Layout Geometry

    private var listWidth: Int { max(cols * 35 / 100, 30) }
    private var detailCol: Int { listWidth + 2 }
    private var detailWidth: Int { cols - listWidth - 2 }
    private var contentTop: Int { 3 } // row 1=status, 2=panel headers, 3+=content
    private var contentHeight: Int { max(rows - 4, 4) } // -1 status -1 headers -1 separator -1 cmd

    // MARK: - Full Render

    private func renderFull() {
        // Fill with dark background
        var buf = ANSI.bgDark + ANSI.fgWhite
        for r in 1...rows {
            buf += ANSI.moveTo(row: r, col: 1) + String(repeating: " ", count: cols)
        }

        buf += renderStatusBar()
        buf += renderPanelHeaders()

        let requests = getFilteredRequests()
        buf += renderListContent(requests)
        buf += renderDetailContent(requests)
        buf += renderBorders()
        buf += renderCommandLineStr()

        ANSI.write(buf)
    }

    // MARK: - Status Bar

    private func renderStatusBar() -> String {
        let watchlist = Watchlist.load()
        let mocks = Config.loadMocks()
        let count = store.count()

        // Left: info
        let left = " 🐱 Pry :\(port)"
        // Center: stats
        let center = "\(watchlist.count) domains │ \(mocks.count) mocks │ \(count) reqs"
        // Right: help + status
        var right = ""
        if let msg = statusMessage {
            right = msg + " "
        } else if let filter = activeFilter {
            right = "[F: \(filter)] Esc clear │ "
        } else if let query = searchQuery {
            right = "[/: \(query)] Esc clear │ "
        }
        right += "c curl │ r repeat │ f filter │ / search │ q quit "

        let padding = max(0, cols - left.count - center.count - right.count)
        let leftPad = padding / 2
        let rightPad = padding - leftPad

        let status = left + String(repeating: " ", count: leftPad) + center + String(repeating: " ", count: rightPad) + right
        let padded = String(status.prefix(cols)).padding(toLength: cols, withPad: " ", startingAt: 0)
        return ANSI.moveTo(row: 1, col: 1) + ANSI.bgStatus + ANSI.fgWhite + ANSI.bold + padded + ANSI.rawReset
    }

    // MARK: - Panel Headers

    private func renderPanelHeaders() -> String {
        var buf = ""

        // List header
        let listHeader = " METHOD  STATUS  HOST"
        let listPadded = String(listHeader.prefix(listWidth - 1)).padding(toLength: listWidth - 1, withPad: " ", startingAt: 0)
        buf += ANSI.moveTo(row: 2, col: 1) + ANSI.bgHeader + ANSI.fgWhite + listPadded + ANSI.rawReset

        // Detail header
        let detailHeader = showMocks ? " 📋 ACTIVE MOCKS" : " 📄 REQUEST / RESPONSE DETAIL"
        let detailPadded = String(detailHeader.prefix(detailWidth)).padding(toLength: detailWidth, withPad: " ", startingAt: 0)
        buf += ANSI.moveTo(row: 2, col: detailCol) + ANSI.bgHeader + ANSI.fgWhite + detailPadded + ANSI.rawReset

        return buf
    }

    // MARK: - Borders

    private func renderBorders() -> String {
        var buf = ""
        // Vertical separator
        for r in 2...(contentTop + contentHeight) {
            buf += ANSI.moveTo(row: r, col: listWidth) + ANSI.bgDark + ANSI.fgGray + "│" + ANSI.reset
        }
        // Bottom separator
        buf += ANSI.moveTo(row: rows - 1, col: 1) + ANSI.bgDark + ANSI.fgGray + String(repeating: "─", count: cols) + ANSI.reset
        return buf
    }

    // MARK: - Request List (Left Panel)

    private func renderList() {
        let requests = getFilteredRequests()
        ANSI.write(renderListContent(requests))
    }

    private func renderListContent(_ requests: [RequestStore.CapturedRequest]) -> String {
        var buf = ""
        let height = contentHeight

        // Adjust scroll
        if selectedIndex < listScrollOffset { listScrollOffset = selectedIndex }
        if selectedIndex >= listScrollOffset + height { listScrollOffset = selectedIndex - height + 1 }

        for i in 0..<height {
            let row = contentTop + i
            let idx = listScrollOffset + i
            buf += ANSI.moveTo(row: row, col: 1)

            if idx < requests.count {
                let req = requests[idx]
                let isSelected = idx == selectedIndex

                // Status indicator
                let statusIcon: String
                let isPaused = RequestBreakpointManager.shared.getPaused().contains { $0.id == req.id }
                if isPaused { statusIcon = "⏸️" }
                else if req.graphqlOperation != nil { statusIcon = "🔮" }
                else if req.isPinned { statusIcon = "📌" }
                else if req.isWebSocket { statusIcon = "🔌" }
                else if req.isMock { statusIcon = "🟡" }
                else if req.isTunnel { statusIcon = "🔒" }
                else if let code = req.statusCode {
                    statusIcon = code < 400 ? "🟢" : "🔴"
                } else { statusIcon = "⏳" }

                let method = req.method.padding(toLength: 7, withPad: " ", startingAt: 0)
                let status = (req.statusCode.map { "\($0)" } ?? "···").padding(toLength: 5, withPad: " ", startingAt: 0)
                let hostMax = listWidth - 18
                let host = String(req.host.prefix(hostMax))

                let line = " \(statusIcon) \(method) \(status) \(host)"
                let padded = String(line.prefix(listWidth - 1)).padding(toLength: listWidth - 1, withPad: " ", startingAt: 0)

                if isSelected {
                    buf += ANSI.bgSelected + ANSI.fgCyanBright + ANSI.bold + padded + ANSI.reset
                } else {
                    buf += ANSI.bgDark + ANSI.fgWhite + padded + ANSI.reset
                }
            } else {
                buf += ANSI.bgDark + String(repeating: " ", count: listWidth - 1) + ANSI.reset
            }
        }
        return buf
    }

    // MARK: - Detail Panel (Right)

    private func renderDetail() {
        let requests = getFilteredRequests()
        ANSI.write(renderDetailContent(requests))
    }

    private func renderDetailContent(_ requests: [RequestStore.CapturedRequest]) -> String {
        var buf = ""
        let sc = detailCol // start col
        let w = detailWidth - 1
        let h = contentHeight

        if showMocks {
            return renderMocksView(startCol: sc, width: w, height: h)
        }

        guard selectedIndex < requests.count else {
            return renderEmptyState(startCol: sc, width: w, height: h)
        }

        let req = requests[selectedIndex]
        let halfH = h / 2
        var line = 0

        // ── Request ──
        let reqTitle = "── Request ─" + String(repeating: "─", count: max(0, w - 13))
        buf += dl(row: contentTop + line, col: sc, w: w, text: ANSI.fgGreen + ANSI.bold + reqTitle + ANSI.reset)
        line += 1

        buf += dl(row: contentTop + line, col: sc, w: w, text: ANSI.fgGreen + " \(req.method) " + ANSI.reset + req.url)
        line += 1

        buf += dl(row: contentTop + line, col: sc, w: w, text: ANSI.dim + " \(req.appIcon) \(req.appName) → \(req.host)" + ANSI.reset)
        line += 1

        for (name, value) in req.requestHeaders.prefix(5) {
            if line >= halfH { break }
            buf += dl(row: contentTop + line, col: sc, w: w, text: ANSI.dim + " \(name): " + ANSI.reset + value)
            line += 1
        }

        if let body = req.requestBody, !body.isEmpty, line < halfH {
            buf += dl(row: contentTop + line, col: sc, w: w, text: ANSI.dim + " Body: " + ANSI.reset + String(body.prefix(w - 7)))
            line += 1
        }

        while line < halfH {
            buf += dl(row: contentTop + line, col: sc, w: w, text: "")
            line += 1
        }

        // ── Response ──
        let respTitle: String
        if req.isTunnel {
            respTitle = "── Tunnel ─" + String(repeating: "─", count: max(0, w - 12))
            buf += dl(row: contentTop + line, col: sc, w: w, text: ANSI.fgGray + ANSI.bold + respTitle + ANSI.reset)
            line += 1
            buf += dl(row: contentTop + line, col: sc, w: w, text: ANSI.fgGray + " 🔒 Encrypted passthrough — not intercepted" + ANSI.reset)
            line += 1
        } else if let code = req.statusCode {
            let color = code < 400 ? ANSI.fgCyan : ANSI.fgRed
            let mockLabel = req.isMock ? " 🟡 MOCK" : ""
            respTitle = "── Response \(code)\(mockLabel) " + String(repeating: "─", count: max(0, w - 18 - mockLabel.count))
            buf += dl(row: contentTop + line, col: sc, w: w, text: color + ANSI.bold + respTitle + ANSI.reset)
            line += 1

            for (name, value) in req.responseHeaders.prefix(5) {
                if line >= h { break }
                buf += dl(row: contentTop + line, col: sc, w: w, text: ANSI.dim + " \(name): " + ANSI.reset + value)
                line += 1
            }

            if let body = req.responseBody, !body.isEmpty {
                let bodyLines = body.split(separator: "\n", omittingEmptySubsequences: false)
                for bodyLine in bodyLines.prefix(h - line) {
                    if line >= h { break }
                    buf += dl(row: contentTop + line, col: sc, w: w, text: " " + String(bodyLine))
                    line += 1
                }
            }
        } else {
            respTitle = "── Response ─" + String(repeating: "─", count: max(0, w - 14))
            buf += dl(row: contentTop + line, col: sc, w: w, text: ANSI.dim + respTitle + ANSI.reset)
            line += 1
            buf += dl(row: contentTop + line, col: sc, w: w, text: ANSI.dim + " ⏳ Waiting..." + ANSI.reset)
            line += 1
        }

        while line < h {
            buf += dl(row: contentTop + line, col: sc, w: w, text: "")
            line += 1
        }

        return buf
    }

    // MARK: - Empty State

    private func renderEmptyState(startCol: Int, width: Int, height: Int) -> String {
        var buf = ""
        let catLines = [
            "   ╱|、",
            "  (˚ˎ 。7",
            "   |、˜〵",
            "   じしˍ,)ノ",
            "",
            "  Waiting for requests...",
            "  Send traffic through :\(port)",
        ]

        let startRow = contentTop + max(0, (height - catLines.count) / 2)
        for i in 0..<height {
            let row = contentTop + i
            if i >= (height - catLines.count) / 2 && (i - (height - catLines.count) / 2) < catLines.count {
                let catIdx = i - (height - catLines.count) / 2
                buf += dl(row: row, col: startCol, w: width, text: ANSI.fgCyan + catLines[catIdx] + ANSI.reset)
            } else {
                buf += dl(row: row, col: startCol, w: width, text: "")
            }
        }
        return buf
    }

    // MARK: - Mocks View

    private func renderMocksView(startCol: Int, width: Int, height: Int) -> String {
        var buf = ""
        let mocks = Config.loadMocks()
        var line = 0

        let title = "── Active Mocks [Tab to close] " + String(repeating: "─", count: max(0, width - 32))
        buf += dl(row: contentTop, col: startCol, w: width, text: ANSI.fgYellow + ANSI.bold + title + ANSI.reset)
        line += 1

        if mocks.isEmpty {
            buf += dl(row: contentTop + line, col: startCol, w: width, text: ANSI.dim + " No mocks registered" + ANSI.reset)
            line += 1
            buf += dl(row: contentTop + line, col: startCol, w: width, text: ANSI.dim + " Use: mock /path '{\"key\":\"value\"}'" + ANSI.reset)
            line += 1
        } else {
            for (path, response) in mocks {
                if line >= height { break }
                buf += dl(row: contentTop + line, col: startCol, w: width, text: ANSI.fgYellow + " ● " + ANSI.reset + path)
                line += 1
                if line < height {
                    let preview = String(response.prefix(width - 6))
                    buf += dl(row: contentTop + line, col: startCol, w: width, text: ANSI.dim + "   → \(preview)" + ANSI.reset)
                    line += 1
                }
            }
        }

        while line < height {
            buf += dl(row: contentTop + line, col: startCol, w: width, text: "")
            line += 1
        }
        return buf
    }

    // MARK: - Command Line

    private func renderCommandLine() {
        ANSI.write(renderCommandLineStr())
    }

    private func renderCommandLineStr() -> String {
        let prompt = " pry❯ "
        let maxInput = cols - prompt.count - 1
        let displayInput = String(commandBuffer.suffix(maxInput))
        let cursorCol = prompt.count + displayInput.count + 1
        let pad = String(repeating: " ", count: max(0, cols - prompt.count - displayInput.count))
        return ANSI.moveTo(row: rows, col: 1) + ANSI.bgDark +
               ANSI.fgCyanBright + ANSI.bold + prompt + ANSI.reset +
               ANSI.bgDark + ANSI.fgWhite + displayInput + pad +
               ANSI.showCursor + ANSI.moveTo(row: rows, col: cursorCol)
    }

    // MARK: - Helpers

    /// Draw line: move to position, fill with panel bg, write text truncated to width
    private func dl(row: Int, col: Int, w: Int, text: String) -> String {
        ANSI.moveTo(row: row, col: col) + ANSI.bgPanel + ANSI.fgWhite + String(repeating: " ", count: w) +
        ANSI.moveTo(row: row, col: col) + ANSI.bgPanel + text + ANSI.reset
    }
}

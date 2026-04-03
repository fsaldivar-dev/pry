import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum ANSI {
    // Cursor
    static func moveTo(row: Int, col: Int) -> String { "\u{001B}[\(row);\(col)H" }
    static func moveUp(_ n: Int = 1) -> String { "\u{001B}[\(n)A" }
    static func moveDown(_ n: Int = 1) -> String { "\u{001B}[\(n)B" }
    static let home = "\u{001B}[H"
    static let saveCursor = "\u{001B}[s"
    static let restoreCursor = "\u{001B}[u"

    // Clear
    static let clearScreen = "\u{001B}[2J"
    static let clearLine = "\u{001B}[2K"
    static let clearToEnd = "\u{001B}[K"

    // Screen buffer
    static let enterAltBuffer = "\u{001B}[?1049h"
    static let exitAltBuffer = "\u{001B}[?1049l"

    // Cursor visibility
    static let hideCursor = "\u{001B}[?25l"
    static let showCursor = "\u{001B}[?25h"

    // Background — always dark
    static let bgDark = "\u{001B}[48;2;13;17;23m"        // #0D1117 — logo background
    static let bgPanel = "\u{001B}[48;2;22;27;34m"       // #161B22 — slightly lighter for panels
    static let bgSelected = "\u{001B}[48;2;33;38;45m"    // #21262D — selected row
    static let bgHeader = "\u{001B}[48;2;40;50;65m"      // #283241 — panel headers
    static let bgStatus = "\u{001B}[48;2;0;100;120m"     // teal status bar

    // Foreground
    static let fgWhite = "\u{001B}[38;2;230;237;243m"    // #E6EDF3 — bright text
    static let fgDim = "\u{001B}[38;2;125;133;144m"      // #7D8590 — dimmed text
    static let fgCyanBright = "\u{001B}[38;2;0;229;255m"  // #00E5FF — logo cyan
    static let fgGreen = "\u{001B}[38;2;63;185;80m"       // #3FB950 — success
    static let fgCyan = "\u{001B}[38;2;88;166;255m"       // #58A6FF — response/info
    static let fgRed = "\u{001B}[38;2;248;81;73m"         // #F85149 — error
    static let fgYellow = "\u{001B}[38;2;210;153;34m"     // #D29922 — mock/warning
    static let fgBlue = "\u{001B}[38;2;88;166;255m"       // #58A6FF — info
    static let fgGray = "\u{001B}[38;2;110;118;129m"      // #6E7681 — tunnel/secondary

    // Style
    static let rawReset = "\u{001B}[0m"
    static let reset = "\u{001B}[0m\u{001B}[48;2;13;17;23m\u{001B}[38;2;230;237;243m" // reset + dark bg + white fg
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let inverse = "\u{001B}[7m"

    // Legacy aliases for Colors.swift compatibility
    static let bgBlue = bgStatus
    static let bgGray = bgHeader

    // Terminal size
    static func getSize() -> (rows: Int, cols: Int) {
        var size = winsize()
        #if canImport(Darwin)
        ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size)
        #else
        ioctl(STDOUT_FILENO, UInt(0x5413), &size) // TIOCGWINSZ on Linux
        #endif
        return (Int(size.ws_row), Int(size.ws_col))
    }

    // Write directly to stdout without buffering
    static func write(_ str: String) {
        var s = str
        s.withUTF8 { ptr in
            _ = Foundation.write(STDOUT_FILENO, ptr.baseAddress!, ptr.count)
        }
    }

    // Draw horizontal line
    static func horizontalLine(row: Int, cols: Int, char: Character = "─") -> String {
        moveTo(row: row, col: 1) + String(repeating: char, count: cols)
    }
}

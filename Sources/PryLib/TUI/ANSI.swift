import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum ANSI {
    // Cursor
    public static func moveTo(row: Int, col: Int) -> String { "\u{001B}[\(row);\(col)H" }
    public static func moveUp(_ n: Int = 1) -> String { "\u{001B}[\(n)A" }
    public static func moveDown(_ n: Int = 1) -> String { "\u{001B}[\(n)B" }
    public static let home = "\u{001B}[H"
    public static let saveCursor = "\u{001B}[s"
    public static let restoreCursor = "\u{001B}[u"

    // Clear
    public static let clearScreen = "\u{001B}[2J"
    public static let clearLine = "\u{001B}[2K"
    public static let clearToEnd = "\u{001B}[K"

    // Screen buffer
    public static let enterAltBuffer = "\u{001B}[?1049h"
    public static let exitAltBuffer = "\u{001B}[?1049l"

    // Cursor visibility
    public static let hideCursor = "\u{001B}[?25l"
    public static let showCursor = "\u{001B}[?25h"

    // Background — always dark
    public static let bgDark = "\u{001B}[48;2;13;17;23m"        // #0D1117 — logo background
    public static let bgPanel = "\u{001B}[48;2;22;27;34m"       // #161B22 — slightly lighter for panels
    public static let bgSelected = "\u{001B}[48;2;33;38;45m"    // #21262D — selected row
    public static let bgHeader = "\u{001B}[48;2;40;50;65m"      // #283241 — panel headers
    public static let bgStatus = "\u{001B}[48;2;0;100;120m"     // teal status bar

    // Foreground
    public static let fgWhite = "\u{001B}[38;2;230;237;243m"    // #E6EDF3 — bright text
    public static let fgDim = "\u{001B}[38;2;125;133;144m"      // #7D8590 — dimmed text
    public static let fgCyanBright = "\u{001B}[38;2;0;229;255m"  // #00E5FF — logo cyan
    public static let fgGreen = "\u{001B}[38;2;63;185;80m"       // #3FB950 — success
    public static let fgCyan = "\u{001B}[38;2;88;166;255m"       // #58A6FF — response/info
    public static let fgRed = "\u{001B}[38;2;248;81;73m"         // #F85149 — error
    public static let fgYellow = "\u{001B}[38;2;210;153;34m"     // #D29922 — mock/warning
    public static let fgBlue = "\u{001B}[38;2;88;166;255m"       // #58A6FF — info
    public static let fgGray = "\u{001B}[38;2;110;118;129m"      // #6E7681 — tunnel/secondary

    // Style
    public static let rawReset = "\u{001B}[0m"
    public static let reset = "\u{001B}[0m\u{001B}[48;2;13;17;23m\u{001B}[38;2;230;237;243m" // reset + dark bg + white fg
    public static let bold = "\u{001B}[1m"
    public static let dim = "\u{001B}[2m"
    public static let inverse = "\u{001B}[7m"

    // Legacy aliases for Colors.swift compatibility
    public static let bgBlue = bgStatus
    public static let bgGray = bgHeader

    // Terminal size
    public static func getSize() -> (rows: Int, cols: Int) {
        var size = winsize()
        #if canImport(Darwin)
        ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size)
        #else
        ioctl(STDOUT_FILENO, UInt(0x5413), &size) // TIOCGWINSZ on Linux
        #endif
        return (Int(size.ws_row), Int(size.ws_col))
    }

    // Write directly to stdout without buffering
    public static func write(_ str: String) {
        var s = str
        s.withUTF8 { ptr in
            _ = Foundation.write(STDOUT_FILENO, ptr.baseAddress!, ptr.count)
        }
    }

    // Draw horizontal line
    public static func horizontalLine(row: Int, cols: Int, char: Character = "─") -> String {
        moveTo(row: row, col: 1) + String(repeating: char, count: cols)
    }
}

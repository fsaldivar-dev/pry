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

    // Style
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let inverse = "\u{001B}[7m"

    // Colors
    static let fgGreen = "\u{001B}[32m"
    static let fgCyan = "\u{001B}[36m"
    static let fgRed = "\u{001B}[31m"
    static let fgYellow = "\u{001B}[33m"
    static let fgBlue = "\u{001B}[34m"
    static let fgGray = "\u{001B}[90m"
    static let fgWhite = "\u{001B}[37m"
    static let bgBlue = "\u{001B}[44m"
    static let bgGray = "\u{001B}[100m"

    // Terminal size
    static func getSize() -> (rows: Int, cols: Int) {
        var size = winsize()
        ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size)
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

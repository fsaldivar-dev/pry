import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum KeyEvent {
    case char(Character)
    case up, down, left, right
    case enter, backspace, delete, tab
    case ctrlC, ctrlD, escape
}

class Terminal {
    private var originalTermios = termios()
    private(set) var isRawMode = false

    func enableRawMode() {
        tcgetattr(STDIN_FILENO, &originalTermios)
        var raw = originalTermios

        // Input: disable break, CR->NL, parity, strip, XON/XOFF
        #if canImport(Darwin)
        raw.c_iflag &= ~UInt(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        raw.c_oflag &= ~UInt(OPOST)
        raw.c_cflag |= UInt(CS8)
        raw.c_lflag &= ~UInt(ECHO | ICANON | IEXTEN | ISIG)
        raw.c_cc.16 = 0  // VMIN
        raw.c_cc.17 = 1  // VTIME (100ms)
        #else
        raw.c_iflag &= ~UInt32(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        raw.c_oflag &= ~UInt32(OPOST)
        raw.c_cflag |= UInt32(CS8)
        raw.c_lflag &= ~UInt32(ECHO | ICANON | IEXTEN | ISIG)
        raw.c_cc.6 = 0   // VMIN (Linux index)
        raw.c_cc.5 = 1   // VTIME (Linux index)
        #endif

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        isRawMode = true
    }

    func disableRawMode() {
        if isRawMode {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
            isRawMode = false
        }
    }

    func readKey() -> KeyEvent? {
        var buf = [UInt8](repeating: 0, count: 3)
        let n = read(STDIN_FILENO, &buf, 1)
        guard n > 0 else { return nil }

        let byte = buf[0]

        // Escape sequence
        if byte == 27 {
            let n2 = read(STDIN_FILENO, &buf, 2)
            if n2 == 2 && buf[0] == 91 { // ESC [
                switch buf[1] {
                case 65: return .up
                case 66: return .down
                case 67: return .right
                case 68: return .left
                default: return .escape
                }
            }
            return .escape
        }

        switch byte {
        case 3: return .ctrlC
        case 4: return .ctrlD
        case 9: return .tab
        case 13: return .enter
        case 127: return .backspace
        default:
            if byte >= 32 && byte < 127 {
                return .char(Character(UnicodeScalar(byte)))
            }
            return nil
        }
    }

    deinit {
        disableRawMode()
    }
}

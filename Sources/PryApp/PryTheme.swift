import SwiftUI
import AppKit

/// Centralized color palette for PryApp — matches the TUI (ANSI.swift).
/// Every hex value comes from Sources/PryLib/TUI/ANSI.swift lines 31-46.
enum PryTheme {

    // MARK: - Backgrounds

    /// Main window / table / sidebar background — very dark blue-gray
    static let bgMain      = Color(red: 13/255, green: 17/255, blue: 23/255)       // #0D1117
    /// Detail panel, code blocks — slightly lighter
    static let bgPanel     = Color(red: 22/255, green: 27/255, blue: 34/255)       // #161B22
    /// Selected row, active hover
    static let bgSelected  = Color(red: 33/255, green: 38/255, blue: 45/255)       // #21262D
    /// Filter bar, picker bar, column headers
    static let bgHeader    = Color(red: 40/255, green: 50/255, blue: 65/255)       // #283241
    /// Status bar — dark teal
    static let bgStatusBar = Color(red: 0/255, green: 100/255, blue: 120/255)      // #006478

    // MARK: - Accent

    /// Primary brand color — cat eyes, selected text, interactive elements
    static let accent      = Color(red: 0/255, green: 229/255, blue: 255/255)      // #00E5FF
    /// Muted blue-cyan — response info, secondary accent
    static let accentMuted = Color(red: 88/255, green: 166/255, blue: 255/255)     // #58A6FF

    // MARK: - Text

    /// Primary text — soft white (NOT pure #FFFFFF)
    static let textPrimary   = Color(red: 230/255, green: 237/255, blue: 243/255)  // #E6EDF3
    /// Secondary text — muted gray
    static let textSecondary = Color(red: 125/255, green: 133/255, blue: 144/255)  // #7D8590
    /// Tertiary text — dimmed, borders
    static let textTertiary  = Color(red: 110/255, green: 118/255, blue: 129/255)  // #6E7681

    // MARK: - Semantic Status

    static let success = Color(red: 16/255, green: 185/255, blue: 129/255)          // #10B981 emerald
    static let error   = Color(red: 239/255, green: 68/255, blue: 68/255)          // #EF4444 modern red
    static let warning = Color(red: 245/255, green: 158/255, blue: 11/255)         // #F59E0B amber

    // MARK: - JSON Syntax

    static let jsonKey    = accent                                                   // #00E5FF cyan
    static let jsonString = success                                                  // #3FB950 green
    static let jsonNumber = warning                                                  // #D29922 amber
    static let jsonBool   = accentMuted                                              // #58A6FF blue
    static let jsonNull   = textSecondary                                            // #7D8590 gray

    // MARK: - NSColor equivalents (for AppKit / NSTableView)

    static let nsBgMain        = NSColor(red: 13/255, green: 17/255, blue: 23/255, alpha: 1)
    static let nsBgPanel       = NSColor(red: 22/255, green: 27/255, blue: 34/255, alpha: 1)
    static let nsBgSelected    = NSColor(red: 33/255, green: 38/255, blue: 45/255, alpha: 1)
    static let nsBgHeader      = NSColor(red: 40/255, green: 50/255, blue: 65/255, alpha: 1)
    static let nsTextPrimary   = NSColor(red: 230/255, green: 237/255, blue: 243/255, alpha: 1)
    static let nsTextSecondary = NSColor(red: 125/255, green: 133/255, blue: 144/255, alpha: 1)
    static let nsTextTertiary  = NSColor(red: 110/255, green: 118/255, blue: 129/255, alpha: 1)
    static let nsAccent        = NSColor(red: 0/255, green: 229/255, blue: 255/255, alpha: 1)
    static let nsSuccess       = NSColor(red: 16/255, green: 185/255, blue: 129/255, alpha: 1)  // #10B981
    static let nsError         = NSColor(red: 239/255, green: 68/255, blue: 68/255, alpha: 1)   // #EF4444
    static let nsWarning       = NSColor(red: 245/255, green: 158/255, blue: 11/255, alpha: 1)  // #F59E0B
    static let nsHover         = NSColor(white: 1, alpha: 0.04)

    /// Status code color for NSTableView cells.
    static func statusColor(_ code: UInt?) -> NSColor {
        guard let code else { return nsTextSecondary }
        switch code {
        case 200..<300: return nsSuccess
        case 300..<400: return nsWarning
        case 400..<500: return nsError
        case 500...:    return NSColor(red: 0.80, green: 0.10, blue: 0.10, alpha: 1)
        default:        return nsTextSecondary
        }
    }
}

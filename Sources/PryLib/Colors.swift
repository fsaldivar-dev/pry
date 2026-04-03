import Foundation

public enum Color: String {
    case green = "\u{001B}[32m"
    case blue = "\u{001B}[34m"
    case cyan = "\u{001B}[36m"
    case red = "\u{001B}[31m"
    case yellow = "\u{001B}[33m"
    case gray = "\u{001B}[90m"
    case bold = "\u{001B}[1m"
    case dim = "\u{001B}[2m"
    case reset = "\u{001B}[0m"
}

public func colored(_ text: String, _ color: Color) -> String {
    "\(color.rawValue)\(text)\(Color.reset.rawValue)"
}

// Semantic helpers
public func request(_ text: String) -> String { colored(text, .green) }
public func response(_ text: String) -> String { colored(text, .cyan) }
public func mock(_ text: String) -> String { colored(text, .yellow) }
public func tunnel(_ text: String) -> String { colored(text, .gray) }
public func errText(_ text: String) -> String { colored(text, .red) }
public func info(_ text: String) -> String { colored(text, .blue) }
public func bold(_ text: String) -> String { colored(text, .bold) }

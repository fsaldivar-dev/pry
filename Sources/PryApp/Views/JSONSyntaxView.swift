import SwiftUI

@available(macOS 14, *)
struct JSONSyntaxView: View {
    let json: String

    @State private var highlighted: AttributedString = AttributedString("")

    var body: some View {
        ScrollView {
            Text(highlighted)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .task(id: json) {
            highlighted = await Task.detached {
                Self.colorize(json)
            }.value
        }
    }

    /// Pretty-prints and colorizes JSON using regex-based token matching.
    nonisolated private static func colorize(_ raw: String) -> AttributedString {
        // Pretty-print first
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let prettyStr = String(data: pretty, encoding: .utf8)
        else {
            return AttributedString(raw)
        }

        var result = AttributedString()

        // Tokenize line by line for simpler processing
        for line in prettyStr.components(separatedBy: "\n") {
            if !result.characters.isEmpty {
                result.append(AttributedString("\n"))
            }
            result.append(colorizeLine(line))
        }
        return result
    }

    nonisolated private static func colorizeLine(_ line: String) -> AttributedString {
        var result = AttributedString()

        // Match: "key" : value patterns
        let keyValuePattern = #"^(\s*)"([^"]+)"(\s*:\s*)(.*)"#
        if let match = try? NSRegularExpression(pattern: keyValuePattern).firstMatch(
            in: line, range: NSRange(line.startIndex..., in: line)
        ) {
            // Indent
            if let r = Range(match.range(at: 1), in: line) {
                result.append(AttributedString(String(line[r])))
            }
            // Key in blue
            if let r = Range(match.range(at: 2), in: line) {
                var key = AttributedString("\"\(line[r])\"")
                key.foregroundColor = .blue
                result.append(key)
            }
            // Colon
            if let r = Range(match.range(at: 3), in: line) {
                result.append(AttributedString(String(line[r])))
            }
            // Value — colorize based on type
            if let r = Range(match.range(at: 4), in: line) {
                result.append(colorizeValue(String(line[r])))
            }
            return result
        }

        // Non key-value line (array elements, braces)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let indent = AttributedString(String(line.prefix(while: { $0 == " " })))
        result.append(indent)
        result.append(colorizeValue(trimmed))
        return result
    }

    nonisolated private static func colorizeValue(_ value: String) -> AttributedString {
        let stripped = value.hasSuffix(",") ? String(value.dropLast()) : value
        let comma = value.hasSuffix(",") ? "," : ""

        var attr: AttributedString

        if stripped.hasPrefix("\"") {
            // String value — green
            attr = AttributedString(stripped)
            attr.foregroundColor = .green
        } else if stripped == "true" || stripped == "false" {
            // Boolean — purple
            attr = AttributedString(stripped)
            attr.foregroundColor = .purple
        } else if stripped == "null" {
            // Null — gray
            attr = AttributedString(stripped)
            attr.foregroundColor = .gray
        } else if Double(stripped) != nil {
            // Number — orange
            attr = AttributedString(stripped)
            attr.foregroundColor = .orange
        } else {
            // Structural ({, }, [, ])
            attr = AttributedString(stripped)
        }

        if !comma.isEmpty {
            attr.append(AttributedString(comma))
        }
        return attr
    }
}

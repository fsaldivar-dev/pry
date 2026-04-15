import Foundation

public struct MapLocal {
    public static var mapsFile: String {
        StoragePaths.ensureRoot()
        return StoragePaths.mapsFile
    }

    public struct MapRule {
        public let regex: String
        public let filePath: String
    }

    public static func save(regex: String, filePath: String) {
        let entry = "\(regex)\t\(filePath)\n"
        if let handle = FileHandle(forWritingAtPath: mapsFile),
           let data = entry.data(using: .utf8) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? entry.write(toFile: mapsFile, atomically: true, encoding: .utf8)
        }
    }

    public static func loadAll() -> [MapRule] {
        guard let content = try? String(contentsOfFile: mapsFile, encoding: .utf8) else { return [] }
        return content.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { return nil }
            return MapRule(regex: parts[0], filePath: parts[1])
        }
    }

    /// Returns file path if URL matches any map rule
    public static func match(url: String) -> String? {
        for rule in loadAll() {
            if let regex = try? NSRegularExpression(pattern: rule.regex),
               regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil {
                return rule.filePath
            }
        }
        return nil
    }

    /// Returns file content if URL matches any map rule
    public static func matchContent(url: String) -> String? {
        guard let filePath = match(url: url) else { return nil }
        // Validate path — prevent path traversal attacks
        let resolved = (filePath as NSString).standardizingPath
        let cwd = FileManager.default.currentDirectoryPath
        guard resolved.hasPrefix(cwd) || resolved.hasPrefix("/tmp/") || resolved.hasPrefix(NSHomeDirectory()) else {
            return nil
        }
        return try? String(contentsOfFile: resolved, encoding: .utf8)
    }

    public static func clear() {
        try? "".write(toFile: mapsFile, atomically: true, encoding: .utf8)
    }
}

import Foundation

public struct SessionManager {
    public static func save(to path: String) throws {
        let requests = RequestStore.shared.getAll()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(requests)
        try data.write(to: URL(fileURLWithPath: path))
    }

    public static func load(from path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let requests = try decoder.decode([RequestStore.CapturedRequest].self, from: data)
        RequestStore.shared.loadEntries(requests)
    }
}

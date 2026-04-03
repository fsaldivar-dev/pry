import XCTest
@testable import PryLib

final class HARExporterTests: XCTestCase {
    func testExportEmpty() {
        let store = RequestStore()
        let har = HARExporter.export(from: store)
        XCTAssertTrue(har.contains("\"log\""))
        XCTAssertTrue(har.contains("\"entries\""))
    }

    func testExportSingleRequest() {
        let store = RequestStore()
        let id = store.addRequest(method: "GET", url: "/api/users", host: "example.com", appIcon: "🖥️", appName: "curl", headers: [("Accept", "application/json")], body: nil)
        store.updateResponse(id: id, statusCode: 200, headers: [("Content-Type", "application/json")], body: "{\"users\":[]}")

        let har = HARExporter.export(from: store)

        // Valid JSON + structure
        let data = har.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let log = json["log"] as! [String: Any]
        XCTAssertEqual(log["version"] as? String, "1.2")
        XCTAssertNotNil(log["creator"])

        let entries = log["entries"] as! [[String: Any]]
        XCTAssertEqual(entries.count, 1)

        let request = entries[0]["request"] as! [String: Any]
        XCTAssertEqual(request["method"] as? String, "GET")
        let url = request["url"] as? String ?? ""
        XCTAssertTrue(url.contains("example.com"))

        let response = entries[0]["response"] as! [String: Any]
        XCTAssertEqual(response["status"] as? Int, 200)
    }

    func testExportMultipleRequests() {
        let store = RequestStore()
        let id1 = store.addRequest(method: "GET", url: "/a", host: "a.com", appIcon: "", appName: "", headers: [], body: nil)
        let id2 = store.addRequest(method: "POST", url: "/b", host: "b.com", appIcon: "", appName: "", headers: [], body: "{\"x\":1}")
        store.updateResponse(id: id1, statusCode: 200, headers: [], body: nil)
        store.updateResponse(id: id2, statusCode: 201, headers: [], body: nil)

        let har = HARExporter.export(from: store)
        let data = har.data(using: .utf8)!
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let log = json["log"] as! [String: Any]
        let entries = log["entries"] as! [[String: Any]]
        XCTAssertEqual(entries.count, 2)
    }
}

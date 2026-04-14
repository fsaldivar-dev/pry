import XCTest
@testable import PryLib

final class ScenarioExporterTests: XCTestCase {
    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "pry-export-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        // Clean scenarios
        for name in ScenarioManager.list() {
            ScenarioManager.delete(name: name)
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
        for name in ScenarioManager.list() {
            ScenarioManager.delete(name: name)
        }
        super.tearDown()
    }

    func testExportAndImport() throws {
        var scenario = Scenario(name: "export-test")
        scenario.watchlist = ["api.example.com"]
        scenario.mocks = [UnifiedMock(pattern: "/api/test", status: 200, body: "{\"ok\":true}")]
        try ScenarioManager.save(scenario)

        let exportPath = "\(tempDir!)/test.pryscenario"
        try ScenarioExporter.export(name: "export-test", to: exportPath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportPath))

        // Verify exported file is valid JSON
        let data = try Data(contentsOf: URL(fileURLWithPath: exportPath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(json["scenario"])
        XCTAssertNotNil(json["exportedAt"])
        XCTAssertNotNil(json["pryVersion"])
    }

    func testImportCreatesScenario() throws {
        var scenario = Scenario(name: "to-import")
        scenario.watchlist = ["test.com"]
        try ScenarioManager.save(scenario)

        let exportPath = "\(tempDir!)/import.pryscenario"
        try ScenarioExporter.export(name: "to-import", to: exportPath)

        // Delete original
        ScenarioManager.delete(name: "to-import")
        XCTAssertNil(ScenarioManager.load(name: "to-import"))

        // Import
        let name = try ScenarioExporter.importScenario(from: exportPath)
        XCTAssertEqual(name, "to-import")
        let imported = ScenarioManager.load(name: "to-import")
        XCTAssertNotNil(imported)
        XCTAssertEqual(imported?.watchlist, ["test.com"])
    }

    func testImportHandlesNameConflict() throws {
        try ScenarioManager.create(name: "conflict")

        var scenario = Scenario(name: "conflict")
        scenario.watchlist = ["new.com"]
        try ScenarioManager.save(scenario)

        let exportPath = "\(tempDir!)/conflict.pryscenario"
        try ScenarioExporter.export(name: "conflict", to: exportPath)

        let importedName = try ScenarioExporter.importScenario(from: exportPath)
        XCTAssertEqual(importedName, "conflict-imported")
        XCTAssertNotNil(ScenarioManager.load(name: "conflict-imported"))
    }

    func testExportNonexistentThrows() {
        XCTAssertThrowsError(try ScenarioExporter.export(name: "nonexistent", to: "\(tempDir!)/out.pryscenario"))
    }
}

import XCTest
@testable import PryLib

final class BodyPrinterTests: XCTestCase {
    func testColorizeJSONKeys() {
        let json = "{\"name\": \"John\"}"
        let result = BodyPrinter.colorizeJSON(json)
        // Keys should have cyan ANSI escape
        XCTAssertTrue(result.contains("\u{001B}[36m"))  // cyan
    }

    func testColorizeJSONStrings() {
        let json = "{\"name\": \"John\"}"
        let result = BodyPrinter.colorizeJSON(json)
        // String values should have green ANSI escape
        XCTAssertTrue(result.contains("\u{001B}[32m"))  // green
    }

    func testColorizeJSONNumbers() {
        let json = "{\"age\": 42}"
        let result = BodyPrinter.colorizeJSON(json)
        // Numbers should have yellow ANSI escape
        XCTAssertTrue(result.contains("\u{001B}[33m"))  // yellow
    }

    func testColorizeJSONBooleans() {
        let json = "{\"active\": true}"
        let result = BodyPrinter.colorizeJSON(json)
        // Booleans should have blue ANSI escape
        XCTAssertTrue(result.contains("\u{001B}[34m"))  // blue
    }

    func testColorizeJSONNull() {
        let json = "{\"data\": null}"
        let result = BodyPrinter.colorizeJSON(json)
        // Null should have gray ANSI escape
        XCTAssertTrue(result.contains("\u{001B}[90m"))  // gray
    }

    func testColorizePreservesStructure() {
        let json = "{\"key\": \"value\"}"
        let result = BodyPrinter.colorizeJSON(json)
        // Should still contain the structural characters
        XCTAssertTrue(result.contains("{"))
        XCTAssertTrue(result.contains("}"))
        XCTAssertTrue(result.contains(":"))
    }
}

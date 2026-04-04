import XCTest
@testable import PryLib

final class BodyPrinterTests: XCTestCase {
    func testColorizeJSONKeys() {
        let json = "{\"name\": \"John\"}"
        let result = BodyPrinter.colorizeJSON(json)
        XCTAssertTrue(result.contains("\u{001B}[36m"))  // cyan for keys
    }

    func testColorizeJSONStrings() {
        let json = "{\"name\": \"John\"}"
        let result = BodyPrinter.colorizeJSON(json)
        XCTAssertTrue(result.contains("\u{001B}[32m"))  // green for strings
    }

    func testColorizeJSONNumbers() {
        let json = "{\"age\": 42}"
        let result = BodyPrinter.colorizeJSON(json)
        XCTAssertTrue(result.contains("\u{001B}[33m"))  // yellow for numbers
    }

    func testColorizeJSONBooleans() {
        let json = "{\"active\": true}"
        let result = BodyPrinter.colorizeJSON(json)
        XCTAssertTrue(result.contains("\u{001B}[34m"))  // blue for bools
    }

    func testColorizeJSONNull() {
        let json = "{\"data\": null}"
        let result = BodyPrinter.colorizeJSON(json)
        XCTAssertTrue(result.contains("\u{001B}[90m"))  // gray for null
    }

    func testColorizePreservesStructure() {
        let json = "{\"key\": \"value\"}"
        let result = BodyPrinter.colorizeJSON(json)
        XCTAssertTrue(result.contains("{"))
        XCTAssertTrue(result.contains("}"))
        XCTAssertTrue(result.contains(":"))
    }
}

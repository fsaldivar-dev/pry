import XCTest
@testable import PryLib

final class ProjectScannerTests: XCTestCase {
    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "pry-scanner-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    func testFindsURLsInSwiftFiles() {
        let swift = """
        let baseURL = "https://api.myapp.com/v1"
        let staging = "https://staging.myapp.com/v1"
        """
        try! swift.write(toFile: tempDir + "/App.swift", atomically: true, encoding: .utf8)

        let domains = ProjectScanner.scan(directory: tempDir)
        XCTAssertTrue(domains.contains("api.myapp.com"))
        XCTAssertTrue(domains.contains("staging.myapp.com"))
    }

    func testExcludesSDKDomains() {
        let swift = """
        let api = "https://api.myapp.com/v1"
        let google = "https://www.googleapis.com/auth"
        let apple = "https://developer.apple.com"
        """
        try! swift.write(toFile: tempDir + "/App.swift", atomically: true, encoding: .utf8)

        let domains = ProjectScanner.scan(directory: tempDir)
        XCTAssertTrue(domains.contains("api.myapp.com"))
        XCTAssertFalse(domains.contains("www.googleapis.com"))
        XCTAssertFalse(domains.contains("developer.apple.com"))
    }

    func testEmptyDirectoryReturnsEmpty() {
        let domains = ProjectScanner.scan(directory: tempDir)
        XCTAssertTrue(domains.isEmpty)
    }

    func testSkipsBuildDirectories() {
        let buildDir = tempDir + "/.build/debug"
        try! FileManager.default.createDirectory(atPath: buildDir, withIntermediateDirectories: true)
        let swift = """
        let url = "https://should.not.find.com/api"
        """
        try! swift.write(toFile: buildDir + "/Generated.swift", atomically: true, encoding: .utf8)

        let domains = ProjectScanner.scan(directory: tempDir)
        XCTAssertFalse(domains.contains("should.not.find.com"))
    }

    func testResultsAreSorted() {
        let swift = """
        let z = "https://zebra.api.com"
        let a = "https://alpha.api.com"
        let m = "https://mid.api.com"
        """
        try! swift.write(toFile: tempDir + "/App.swift", atomically: true, encoding: .utf8)

        let domains = ProjectScanner.scan(directory: tempDir)
        XCTAssertEqual(domains, domains.sorted())
    }
}

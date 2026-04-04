import XCTest
@testable import PryLib

final class CertificatePinningDetectorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RequestStore.shared.clear()
    }

    override func tearDown() {
        RequestStore.shared.clear()
        super.tearDown()
    }

    func testMarkPinned() {
        let id = RequestStore.shared.addRequest(
            method: "CONNECT",
            url: "secure.bank.com",
            host: "secure.bank.com",
            appIcon: "📌",
            appName: "pinned",
            headers: [],
            body: nil
        )
        RequestStore.shared.markPinned(id: id)

        let req = RequestStore.shared.get(id: id)
        XCTAssertNotNil(req)
        XCTAssertTrue(req!.isPinned)
    }

    func testNonPinnedRequestDefaultsFalse() {
        let id = RequestStore.shared.addRequest(
            method: "GET",
            url: "/api/test",
            host: "example.com",
            appIcon: "🌐",
            appName: "browser",
            headers: [],
            body: nil
        )
        let req = RequestStore.shared.get(id: id)
        XCTAssertNotNil(req)
        XCTAssertFalse(req!.isPinned)
    }
}

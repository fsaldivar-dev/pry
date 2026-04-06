import XCTest
import PryLib
@testable import PryKit

@available(macOS 14, *)
final class ProxyManagerTests: XCTestCase {

    @MainActor
    func testStartSetsRunning() throws {
        let manager = ProxyManager(port: 18_091)
        try manager.start()
        XCTAssertTrue(manager.isRunning)
        manager.stop()
    }

    @MainActor
    func testStopClearsRunning() throws {
        let manager = ProxyManager(port: 18_092)
        try manager.start()
        manager.stop()
        XCTAssertFalse(manager.isRunning)
    }

    @MainActor
    func testStartFailsOnBadPort() {
        let manager = ProxyManager(port: -1)
        XCTAssertThrowsError(try manager.start())
        XCTAssertFalse(manager.isRunning)
    }

    @MainActor
    func testAddDomainUpdatesArray() {
        let domain = "prykit-add-\(Int.random(in: 10000...99999)).example.com"
        let manager = ProxyManager(port: 18_093)
        manager.reloadDomains()
        XCTAssertFalse(manager.domains.contains(domain))
        manager.addDomain(domain)
        XCTAssertTrue(manager.domains.contains(domain))
        manager.removeDomain(domain)
    }

    @MainActor
    func testRemoveDomainUpdatesArray() {
        let domain = "prykit-remove-\(Int.random(in: 10000...99999)).example.com"
        let manager = ProxyManager(port: 18_094)
        manager.addDomain(domain)
        XCTAssertTrue(manager.domains.contains(domain))
        manager.removeDomain(domain)
        XCTAssertFalse(manager.domains.contains(domain))
    }
}

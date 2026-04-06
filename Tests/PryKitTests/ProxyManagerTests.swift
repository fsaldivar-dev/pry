import Testing
import PryLib
@testable import PryKit

@Suite("ProxyManager")
struct ProxyManagerTests {

    @available(macOS 14, *)
    @Test func startSetsRunning() async throws {
        let manager = await ProxyManager(port: 18_091)
        try await manager.start()
        #expect(await manager.isRunning == true)
        await manager.stop()
    }

    @available(macOS 14, *)
    @Test func stopClearsRunning() async throws {
        let manager = await ProxyManager(port: 18_092)
        try await manager.start()
        await manager.stop()
        #expect(await manager.isRunning == false)
    }

    @available(macOS 14, *)
    @Test func startFailsOnBadPort() async {
        let manager = await ProxyManager(port: -1)
        do {
            try await manager.start()
            Issue.record("Expected start() to throw on invalid port")
        } catch {
            #expect(await manager.isRunning == false)
        }
    }

    @available(macOS 14, *)
    @Test func addDomainUpdatesArray() async {
        let domain = "prykit-add-\(Int.random(in: 10000...99999)).example.com"
        let manager = await ProxyManager(port: 18_093)
        await manager.reloadDomains()
        #expect(await manager.domains.contains(domain) == false)
        await manager.addDomain(domain)
        #expect(await manager.domains.contains(domain) == true)
        // Cleanup
        await manager.removeDomain(domain)
    }

    @available(macOS 14, *)
    @Test func removeDomainUpdatesArray() async {
        let domain = "prykit-remove-\(Int.random(in: 10000...99999)).example.com"
        let manager = await ProxyManager(port: 18_094)
        await manager.addDomain(domain)
        #expect(await manager.domains.contains(domain) == true)
        await manager.removeDomain(domain)
        #expect(await manager.domains.contains(domain) == false)
    }
}

import XCTest
@testable import PryLib

final class WatchdogTests: XCTestCase {

    // MARK: - Logic via dependency injection
    //
    // Los tests evitan spawnear procesos reales o dormir por segundos.
    // Se inyecta `processAlive`, `sentinelExists` y `sleep` para controlar
    // el loop de forma determinística.

    func testExitsWhenProcessDies_runsCleanup() {
        // El proceso muere en la iteración 2. El cleanup debe ejecutarse exactamente una vez.
        var aliveCallCount = 0
        let aliveStub: @Sendable (pid_t) -> Bool = { _ in
            aliveCallCount += 1
            return aliveCallCount < 2   // iteración 1: alive, iteración 2: dead
        }

        var cleanupCalls = 0
        let cleanup: @Sendable () -> Void = { cleanupCalls += 1 }

        let result = Watchdog.run(
            parentPID: 99999,
            pollInterval: 0.01,
            processAlive: aliveStub,
            sentinelExists: { _ in false },
            sleep: { _ in },
            onCleanup: cleanup
        )

        XCTAssertEqual(result, .cleanupExecuted)
        XCTAssertEqual(cleanupCalls, 1, "cleanup debería ejecutarse exactamente una vez")
    }

    func testExitsSilentlyWhenSentinelPresent_doesNotCleanup() {
        // Sentinel presente desde el arranque → salida silenciosa, sin tocar proxy.
        var cleanupCalls = 0
        let cleanup: @Sendable () -> Void = { cleanupCalls += 1 }

        let result = Watchdog.run(
            parentPID: 12345,
            pollInterval: 0.01,
            processAlive: { _ in true }, // aunque el padre siga vivo
            sentinelExists: { _ in true },
            sleep: { _ in XCTFail("no debería dormir — sale en la primera iteración") },
            onCleanup: cleanup
        )

        XCTAssertEqual(result, .silentExit)
        XCTAssertEqual(cleanupCalls, 0, "cleanup NO debería ejecutarse cuando hay sentinel")
    }

    func testSentinelWinsEvenIfProcessAlsoDead() {
        // Si aparecen ambas condiciones a la vez (sentinel + padre muerto),
        // el sentinel manda → no hacemos cleanup. Esto es el ordering correcto
        // para evitar que `stop()` de PryApp (que escribe sentinel y luego mata
        // system proxy él mismo) se pise con el watchdog.
        var cleanupCalls = 0
        let cleanup: @Sendable () -> Void = { cleanupCalls += 1 }

        let result = Watchdog.run(
            parentPID: 12345,
            pollInterval: 0.01,
            processAlive: { _ in false },
            sentinelExists: { _ in true },
            sleep: { _ in },
            onCleanup: cleanup
        )

        XCTAssertEqual(result, .silentExit)
        XCTAssertEqual(cleanupCalls, 0)
    }

    func testContinuesPollingWhileProcessAlive() {
        // Padre siempre vivo, sin sentinel → debería hacer exactamente `maxIterations` polls
        // y cortar con `.maxIterationsReached` sin llamar cleanup.
        var aliveCalls = 0
        var sleepCalls = 0
        var cleanupCalls = 0

        let result = Watchdog.run(
            parentPID: 12345,
            pollInterval: 0.01,
            processAlive: { _ in
                aliveCalls += 1
                return true
            },
            sentinelExists: { _ in false },
            sleep: { _ in sleepCalls += 1 },
            onCleanup: { cleanupCalls += 1 },
            maxIterations: 5
        )

        XCTAssertEqual(result, .maxIterationsReached)
        XCTAssertEqual(aliveCalls, 5, "debería hacer 5 polls exactos")
        // Sleep corre entre polls; tras el 5º poll cortamos antes de dormir.
        XCTAssertEqual(sleepCalls, 4, "debería dormir 4 veces entre 5 polls")
        XCTAssertEqual(cleanupCalls, 0, "cleanup NO debería ejecutarse mientras el padre vive")
    }

    func testSentinelPathUsesParentPID() {
        // El path del sentinel debe ser estable y contener el parent PID para
        // evitar colisiones si hay múltiples PryApp running (caso raro pero
        // posible durante dev/tests).
        let path1 = Watchdog.sentinelPath(for: 1234)
        let path2 = Watchdog.sentinelPath(for: 5678)
        XCTAssertNotEqual(path1, path2)
        XCTAssertTrue(path1.contains("1234"))
        XCTAssertTrue(path2.contains("5678"))
        XCTAssertTrue(path1.contains("watchdog-shutdown"))
    }

    // MARK: - Real process checks

    func testDefaultProcessAliveReturnsTrueForCurrentPID() {
        // El proceso del test suite está vivo, obviamente.
        let myPid = ProcessInfo.processInfo.processIdentifier
        XCTAssertTrue(Watchdog.defaultProcessAlive(myPid))
    }

    func testDefaultProcessAliveReturnsFalseForImpossiblePID() {
        // PID 999999 casi seguro no existe (max PID en macOS es típicamente ~99999).
        XCTAssertFalse(Watchdog.defaultProcessAlive(999999))
    }

    // MARK: - Sentinel file checks

    func testDefaultSentinelExistsWorksWithRealFS() {
        let tempPath = NSTemporaryDirectory() + "watchdog-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        XCTAssertFalse(Watchdog.defaultSentinelExists(tempPath))
        FileManager.default.createFile(atPath: tempPath, contents: Data())
        XCTAssertTrue(Watchdog.defaultSentinelExists(tempPath))
    }
}

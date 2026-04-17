import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Watchdog — proceso hijo que monitorea al padre (PryApp) y limpia el
/// system proxy si el padre muere de forma abrupta (SIGKILL, force-quit, crash).
///
/// Sin el watchdog: si PryApp es force-quit mientras el system proxy está en
/// `localhost:8080`, el Mac pierde toda la red hasta que alguien relance Pry
/// (que llamaría `ProxyGuard.cleanupIfNeeded()` en el launch).
///
/// Con el watchdog: un `pry --watchdog <parent_pid>` spawned como detached
/// child observa al padre con `kill(pid, 0)` cada 3s. Si el padre muere →
/// disable el system proxy. Si el padre hace Stop ordenado, crea un sentinel
/// file para que el watchdog salga sin tocar el proxy state.
public enum Watchdog {

    /// Intervalo de polling por default (3 segundos, como describe el issue).
    public static let defaultPollInterval: TimeInterval = 3.0

    /// Path del sentinel file para un parent PID dado.
    /// Si existe cuando el watchdog verifica, significa "shutdown limpio en curso,
    /// no limpies nada".
    public static func sentinelPath(for parentPID: pid_t) -> String {
        "\(StoragePaths.root)/watchdog-shutdown-\(parentPID)"
    }

    /// Default implementation de `processAlive`: usa `kill(pid, 0)` para
    /// comprobar si un proceso existe. Devuelve false si la llamada falla
    /// con ESRCH (no such process).
    public static let defaultProcessAlive: @Sendable (pid_t) -> Bool = { pid in
        // kill con signal 0 no envía nada, solo chequea si el proceso existe
        // y si tenemos permiso para enviarle señales. Retorna 0 si existe.
        if kill(pid, 0) == 0 { return true }
        // errno == ESRCH significa que el proceso no existe
        return errno != ESRCH
    }

    /// Default implementation de `sentinelExists`: chequea el filesystem.
    public static let defaultSentinelExists: @Sendable (String) -> Bool = { path in
        FileManager.default.fileExists(atPath: path)
    }

    /// Resultado del run del watchdog.
    public enum RunResult: Equatable {
        /// El padre murió y se ejecutó el cleanup (disable system proxy).
        case cleanupExecuted
        /// El sentinel file estaba presente (shutdown limpio), salida silenciosa.
        case silentExit
        /// Se alcanzó el tope de iteraciones (solo usado en tests).
        case maxIterationsReached
    }

    /// Cleanup default: disable system proxy + clear proxy state + remove pid file.
    /// Esto es lo mismo que haría ProxyGuard ante un orphan, pero sin chequeos de
    /// orphan porque acá ya sabemos que el padre murió.
    public static let defaultCleanup: @Sendable () -> Void = {
        if let state = ProxyState.load() {
            SystemProxy.disable(service: state.networkService)
        } else {
            SystemProxy.disable()
        }
        ProxyState.clear()
        try? FileManager.default.removeItem(atPath: Config.pidFile)
    }

    /// Ejecuta el loop del watchdog. Diseñado para ser testeable mediante
    /// inyección de dependencias (processAlive, sentinelExists, sleep, onCleanup).
    ///
    /// - Parameters:
    ///   - parentPID: PID del proceso padre a monitorear.
    ///   - pollInterval: Intervalo entre polls (default 3s, override en tests).
    ///   - processAlive: Predicado para chequear si un PID está vivo.
    ///   - sentinelExists: Predicado para chequear si el sentinel file existe.
    ///   - sleep: Función de sleep (default `Thread.sleep`), override en tests.
    ///   - onCleanup: Acción a ejecutar si el padre muere sin sentinel.
    ///                Default: disable system proxy + clear state + remove pid file.
    ///   - maxIterations: Tope opcional de iteraciones (para tests). nil = sin límite.
    /// - Returns: El resultado del run (cleanup ejecutado, silent exit, o tope de iteraciones).
    @discardableResult
    public static func run(
        parentPID: pid_t,
        pollInterval: TimeInterval = Watchdog.defaultPollInterval,
        processAlive: @Sendable (pid_t) -> Bool = Watchdog.defaultProcessAlive,
        sentinelExists: @Sendable (String) -> Bool = Watchdog.defaultSentinelExists,
        sleep: @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        onCleanup: @Sendable () -> Void = Watchdog.defaultCleanup,
        maxIterations: Int? = nil
    ) -> RunResult {
        let sentinel = sentinelPath(for: parentPID)
        var iterations = 0
        while true {
            // 1. Sentinel file? El padre anunció un shutdown limpio → salir sin tocar nada.
            if sentinelExists(sentinel) {
                fputs("[pry-watchdog] sentinel detected for pid \(parentPID), exiting silently\n", stderr)
                return .silentExit
            }
            // 2. Padre muerto? → cleanup y salir.
            if !processAlive(parentPID) {
                fputs("[pry-watchdog] parent pid \(parentPID) is gone, cleaning up system proxy\n", stderr)
                onCleanup()
                return .cleanupExecuted
            }
            // 3. Padre vivo, sin sentinel → seguir mirando.
            iterations += 1
            if let max = maxIterations, iterations >= max {
                return .maxIterationsReached
            }
            sleep(pollInterval)
        }
    }
}

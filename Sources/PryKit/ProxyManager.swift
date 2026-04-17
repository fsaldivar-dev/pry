import Foundation
import Observation
import PryLib

/// @Observable bridge over ProxyServer, Watchlist, and Config for SwiftUI.
@available(macOS 14, *)
@Observable
@MainActor
public final class ProxyManager {
    public var isRunning = false
    public var port: Int
    public var requestCount: Int = 0
    public var domains: [String] = []
    public var systemProxyEnabled = false
    /// True cuando el watchdog subprocess está corriendo y monitoreando a PryApp.
    /// Si es false después de un `start()`, probablemente no encontramos el binario `pry`
    /// — el proxy funciona igual, pero sin protección contra force-quit del Mac.
    public var watchdogRunning: Bool = false
    /// Mensaje efímero a mostrar como banner en la GUI (toasts de acción).
    /// Se setea tras operaciones que requieren que el usuario entienda el efecto
    /// (ej. agregar dominio al watchlist con proxy corriendo). La UI limpia después de mostrarlo.
    public var statusBanner: String?

    private let serverBox = ServerBox()
    private let watchdogBox = WatchdogBox()

    public init(port: Int = Config.port()) {
        self.port = port
        // Check for orphaned proxy config from a previous crash
        ProxyGuard.cleanupIfNeeded()
    }

    /// Arranca el proxy. Si se provee `interceptors`, la arquitectura nueva (ADR-006)
    /// ejecuta su chain antes del flow legacy en cada request — features como
    /// BlockInterceptor, MockInterceptor, etc. corren de verdad en el pipeline.
    ///
    /// Si `interceptors` es nil (ej. CLI headless), el proxy funciona con sólo
    /// el flow legacy (BlockList.shared, MockEngine.shared, etc.) como antes.
    public func start(interceptors: InterceptorRegistry? = nil) throws {
        let s = ProxyServer(port: port, interceptors: interceptors)
        try s.start()
        serverBox.server = s
        isRunning = true
        reloadDomains()
        // Auto-enable system proxy so traffic flows through Pry
        enableSystemProxy()
        // Spawn watchdog: si PryApp es force-quit (SIGKILL), el watchdog restaura
        // el system proxy para que el Mac no se quede sin red.
        spawnWatchdog()
    }

    public func stop() {
        // Write sentinel + terminate watchdog BEFORE disabling proxy, para evitar
        // que el watchdog gane la carrera y "limpie" algo que estamos limpiando nosotros.
        shutdownWatchdog()
        // Restore system proxy before shutting down
        disableSystemProxy()
        serverBox.shutdownIfNeeded()
        isRunning = false
    }

    public func enableSystemProxy() {
        SystemProxy.enable(port: port)
        systemProxyEnabled = true
    }

    public func disableSystemProxy() {
        if systemProxyEnabled {
            SystemProxy.disable()
            systemProxyEnabled = false
        }
    }

    public func reloadDomains() {
        domains = Watchlist.load().sorted()
    }

    /// Agrega un dominio al watchlist. Si el proxy está corriendo + system proxy activo,
    /// hace un toggle breve del system proxy para forzar que los clientes (browsers, apps)
    /// tiren sus conexiones HTTPS keep-alive existentes y re-establezcan nuevas conexiones
    /// que van a pasar por `ConnectHandler` con la decisión `shouldIntercept` actualizada.
    ///
    /// Sin este toggle, las conexiones TCP ya-vivas al host recién agregado siguen
    /// tunneling sin interceptar hasta que el cliente las cierre naturalmente — lo que
    /// forzaba a los usuarios a hacer Stop/Start del proxy manualmente.
    public func addDomain(_ domain: String) {
        Watchlist.add(domain)
        reloadDomains()
        if isRunning && systemProxyEnabled {
            forceProxyReconnect()
            statusBanner = "Dominio agregado: \(domain). Si no ves HTTPS en segundos, hacé una nueva request o reiniciá el cliente."
        }
    }

    /// Toggle breve del system proxy para forzar a los clientes a tirar sus conexiones
    /// keep-alive. La pausa de ~150ms es suficiente para que `networksetup` notifique
    /// el cambio a nivel OS sin alcanzar a que las apps fallen requests en curso.
    private func forceProxyReconnect() {
        SystemProxy.disable()
        // Pequeña pausa síncrona para que la notificación llegue antes de re-enable.
        usleep(150_000)
        SystemProxy.enable(port: port)
    }

    /// Limpia el banner de estado (llamado por la UI tras mostrarlo).
    public func dismissStatusBanner() {
        statusBanner = nil
    }

    public func removeDomain(_ domain: String) {
        Watchlist.remove(domain)
        reloadDomains()
    }

    // MARK: - Watchdog

    /// Spawnea `pry --watchdog <getpid()>` como proceso detached. Si PryApp es
    /// force-quit (kill -9) o crashea, el watchdog detecta al padre muerto y
    /// restaura el system proxy — sin él, el Mac quedaría sin red hasta la
    /// próxima vez que alguien ejecute `pry`.
    private func spawnWatchdog() {
        if watchdogBox.isRunning { return }
        guard let binary = resolvePryBinary() else {
            fputs("[ProxyManager] Warning: no se encontró el binario `pry`, watchdog deshabilitado. Si PryApp cae abruptamente, ejecutar `pry start` o `pry stop` restaurará la red.\n", stderr)
            watchdogRunning = false
            return
        }
        let ppid = ProcessInfo.processInfo.processIdentifier
        // Limpiar cualquier sentinel stale de un ciclo anterior del mismo PID.
        try? FileManager.default.removeItem(atPath: Watchdog.sentinelPath(for: ppid))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["--watchdog", "\(ppid)"]
        // Descartar stdout/stderr del watchdog para no contaminar la GUI.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            watchdogBox.set(process: process, parentPID: ppid)
            watchdogRunning = true
        } catch {
            fputs("[ProxyManager] Failed to spawn watchdog: \(error)\n", stderr)
            watchdogRunning = false
        }
    }

    /// Shutdown ordenado del watchdog: escribe sentinel, llama `.terminate()`,
    /// espera brevemente, borra sentinel.
    private func shutdownWatchdog() {
        watchdogBox.shutdownGracefully(timeout: 1.0)
        watchdogRunning = false
    }

    /// Intenta resolver el path del binario `pry`:
    /// 1. Sibling del ejecutable actual (dentro de `PryApp.app/Contents/MacOS/pry`)
    /// 2. `/usr/local/bin/pry` (Homebrew Intel / make install)
    /// 3. `/opt/homebrew/bin/pry` (Homebrew Apple Silicon)
    /// Devuelve nil si ningún candidato es ejecutable — el caller loguea warning.
    private func resolvePryBinary() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let exec = Bundle.main.executablePath {
            let sibling = (exec as NSString).deletingLastPathComponent + "/pry"
            candidates.append(sibling)
        }
        candidates.append("/usr/local/bin/pry")
        candidates.append("/opt/homebrew/bin/pry")
        for c in candidates where fm.isExecutableFile(atPath: c) {
            return c
        }
        return nil
    }

    deinit {
        // Belt-and-suspenders: si llegamos acá sin haber llamado stop(),
        // apagar watchdog y system proxy. Usamos el box (Sendable) porque
        // deinit no puede invocar métodos MainActor-isolated.
        watchdogBox.shutdownGracefully(timeout: 0.5)
        SystemProxy.disable()
        ProxyState.clear()
        serverBox.shutdownIfNeeded()
    }
}

/// Thread-safe box to hold ProxyServer reference, enabling deinit access
/// without violating MainActor isolation.
private final class ServerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _server: ProxyServer?

    var server: ProxyServer? {
        get { lock.withLock { _server } }
        set { lock.withLock { _server = newValue } }
    }

    func shutdownIfNeeded() {
        lock.withLock {
            _server?.shutdown()
            _server = nil
        }
    }
}

/// Thread-safe box para el Process del watchdog, permite acceso desde `deinit`
/// sin violar aislamiento de MainActor.
private final class WatchdogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _process: Process?
    private var _parentPID: pid_t?

    var isRunning: Bool {
        lock.withLock { _process?.isRunning ?? false }
    }

    func set(process: Process, parentPID: pid_t) {
        lock.withLock {
            _process = process
            _parentPID = parentPID
        }
    }

    /// Shutdown limpio: escribe sentinel, termina el proceso, espera hasta `timeout`,
    /// borra sentinel, limpia referencias. Idempotente.
    func shutdownGracefully(timeout: TimeInterval) {
        // Capturar referencias bajo lock, trabajar fuera del lock para no bloquear.
        let (process, ppid): (Process?, pid_t?) = lock.withLock { (_process, _parentPID) }
        guard let process = process, let ppid = ppid else { return }
        let sentinel = Watchdog.sentinelPath(for: ppid)
        StoragePaths.ensureRoot()
        FileManager.default.createFile(atPath: sentinel, contents: Data())
        if process.isRunning {
            process.terminate()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        try? FileManager.default.removeItem(atPath: sentinel)
        lock.withLock {
            _process = nil
            _parentPID = nil
        }
    }
}

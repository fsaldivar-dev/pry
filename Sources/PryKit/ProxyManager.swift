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
    /// Mensaje efímero a mostrar como banner en la GUI (toasts de acción).
    /// Se setea tras operaciones que requieren que el usuario entienda el efecto
    /// (ej. agregar dominio al watchlist con proxy corriendo). La UI limpia después de mostrarlo.
    public var statusBanner: String?

    private let serverBox = ServerBox()

    public init(port: Int = Config.port()) {
        self.port = port
        // Check for orphaned proxy config from a previous crash
        ProxyGuard.cleanupIfNeeded()
    }

    public func start() throws {
        let s = ProxyServer(port: port)
        try s.start()
        serverBox.server = s
        isRunning = true
        reloadDomains()
        // Auto-enable system proxy so traffic flows through Pry
        enableSystemProxy()
    }

    public func stop() {
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

    deinit {
        // Ensure system proxy is restored even on unexpected termination
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

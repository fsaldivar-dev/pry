import Foundation

/// Marker protocol para todo evento publicable al `EventBus`.
///
/// Los eventos son value types `Sendable` con los datos mínimos para reaccionar.
/// **No incluyen bodies** — si un subscriber los necesita, accede al store
/// correspondiente por id.
public protocol PryEvent: Sendable {}

// MARK: - Ciclo de vida de request

/// Emitido cuando el proxy captura una request — después de que la chain pasó
/// (o decidió short-circuit), antes del forward al servidor real.
///
/// Payload completo incluye headers + body para soportar observers que graban
/// el tráfico (ej. RecordingsStore). Consumers livianos (UI counters) pueden
/// ignorar los campos pesados.
///
/// `requestID` es un `Int` incremental compatible con `RequestStore` legacy,
/// permite correlación con `ResponseReceivedEvent` del mismo request.
public struct RequestCapturedEvent: PryEvent {
    public let requestID: Int
    public let method: String
    public let host: String
    public let url: String           // path + query
    public let headers: [(String, String)]
    public let body: String?
    public let capturedAt: Date

    public init(requestID: Int, method: String, host: String, url: String,
                headers: [(String, String)], body: String?, capturedAt: Date = Date()) {
        self.requestID = requestID
        self.method = method
        self.host = host
        self.url = url
        self.headers = headers
        self.body = body
        self.capturedAt = capturedAt
    }
}

/// Emitido cuando la response está lista (del servidor o short-circuit).
public struct ResponseReceivedEvent: PryEvent {
    public let requestID: Int
    public let status: UInt
    public let headers: [(String, String)]
    public let body: String?
    public let latencyMs: Int
    public let isMock: Bool

    public init(requestID: Int, status: UInt, headers: [(String, String)],
                body: String?, latencyMs: Int, isMock: Bool) {
        self.requestID = requestID
        self.status = status
        self.headers = headers
        self.body = body
        self.latencyMs = latencyMs
        self.isMock = isMock
    }
}

/// Emitido cuando un interceptor retorna `.pause` — la request quedó en espera de
/// resolución externa (típicamente de la UI de Breakpoints).
public struct RequestPausedEvent: PryEvent {
    public let requestID: UUID
    public let pausedAt: Date

    public init(requestID: UUID, pausedAt: Date = Date()) {
        self.requestID = requestID
        self.pausedAt = pausedAt
    }
}

// MARK: - Lifecycle global

/// Emitido cuando el usuario limpia el historial de tráfico (botón "Clear").
/// Los subscribers (UI, recorder, etc.) deben reaccionar vaciando sus caches.
public struct TrafficClearedEvent: PryEvent {
    public let clearedAt: Date
    public init(clearedAt: Date = Date()) { self.clearedAt = clearedAt }
}

// MARK: - Tunnels (CONNECT / TLS)

/// Un tunnel HTTPS CONNECT se estableció hacia `host:port`. El tráfico encriptado
/// dentro del tunnel produce sus propios `RequestCapturedEvent` si hay intercepción.
public struct TunnelOpenedEvent: PryEvent {
    public let tunnelID: UUID
    public let host: String
    public let port: Int
    public let openedAt: Date

    public init(tunnelID: UUID, host: String, port: Int, openedAt: Date = Date()) {
        self.tunnelID = tunnelID
        self.host = host
        self.port = port
        self.openedAt = openedAt
    }
}

/// Un tunnel se cerró (por fin de sesión, timeout, o error).
public struct TunnelClosedEvent: PryEvent {
    public let tunnelID: UUID
    public let closedAt: Date
    public init(tunnelID: UUID, closedAt: Date = Date()) {
        self.tunnelID = tunnelID
        self.closedAt = closedAt
    }
}

// MARK: - Feature-specific events

/// Emitido cuando la lista de dominios bloqueados cambia (add/remove/clear).
/// Consumers: UI de otras features, futuro Recorder, métricas, etc.
public struct BlockListChangedEvent: PryEvent {
    public let domains: [String]
    public let changedAt: Date
    public init(domains: [String], changedAt: Date = Date()) {
        self.domains = domains
        self.changedAt = changedAt
    }
}

/// Emitido cuando la lista de status overrides cambia (add/remove/clear).
/// Consumers: UI de otras features, métricas, futuras integraciones.
///
/// El payload lleva la lista actual de `(pattern, status)` — sin cuerpos ni metadata
/// adicional — siguiendo la convención de eventos livianos del `EventBus`.
public struct StatusOverridesChangedEvent: PryEvent {
    public let overrides: [(String, Int)]
    public let changedAt: Date
    public init(overrides: [(String, Int)], changedAt: Date = Date()) {
        self.overrides = overrides
        self.changedAt = changedAt
    }
}

/// Emitido cuando la lista de mappings de MapLocal cambia.
/// Consumers: UI, futuras integraciones.
/// Payload: `(pattern, filePath)` para cada mapping.
public struct MapLocalChangedEvent: PryEvent {
    public let mappings: [(String, String)]
    public let changedAt: Date
    public init(mappings: [(String, String)], changedAt: Date = Date()) {
        self.mappings = mappings
        self.changedAt = changedAt
    }
}

/// Emitido cuando la lista de host redirects (MapRemote migrado) cambia.
/// Payload: `(sourceHost, targetHost)` por cada redirect.
public struct HostRedirectsChangedEvent: PryEvent {
    public let redirects: [(String, String)]
    public let changedAt: Date
    public init(redirects: [(String, String)], changedAt: Date = Date()) {
        self.redirects = redirects
        self.changedAt = changedAt
    }
}

/// Emitido cuando las reglas de rewrite de headers cambian.
/// Payload: `(action, name, value)` donde `action` es "set" o "remove".
public struct HeaderRulesChangedEvent: PryEvent {
    public let rules: [(String, String, String)]
    public let changedAt: Date
    public init(rules: [(String, String, String)], changedAt: Date = Date()) {
        self.rules = rules
        self.changedAt = changedAt
    }
}

/// Emitido cuando la lista de DNS overrides cambia.
/// Payload: `(domain, ip)` por cada override.
public struct DNSOverridesChangedEvent: PryEvent {
    public let overrides: [(String, String)]
    public let changedAt: Date
    public init(overrides: [(String, String)], changedAt: Date = Date()) {
        self.overrides = overrides
        self.changedAt = changedAt
    }
}

/// Emitido cuando cambia el estado de grabación (start/stop) o la lista
/// de grabaciones guardadas (delete).
public struct RecordingsChangedEvent: PryEvent {
    public let names: [String]
    public let isRecording: Bool
    public let changedAt: Date
    public init(names: [String], isRecording: Bool, changedAt: Date = Date()) {
        self.names = names
        self.isRecording = isRecording
        self.changedAt = changedAt
    }
}

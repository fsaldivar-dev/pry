import Foundation

/// Contrato único para features que **mutan** el flow del proxy.
///
/// Implementaciones típicas: `BlockInterceptor` (gate), `MockInterceptor` (resolve),
/// `HeaderRewriteInterceptor` (transform), `ThrottleInterceptor` (network).
///
/// Si una feature sólo **observa** sin mutar (UI, Recorder, métricas), NO implementa
/// este protocolo — suscribe al `EventBus` en su lugar.
///
/// Los interceptors se ejecutan en orden de `phase` (ver `Phase`). Dentro de una
/// misma phase el orden es de registro (FIFO).
public protocol Interceptor: Sendable {
    /// Fase en la que corre este interceptor. Define el orden global del pipeline.
    var phase: Phase { get }

    /// Procesa una request. Retorna un `InterceptResult` que indica cómo continúa
    /// el pipeline.
    ///
    /// - Parameter ctx: la request actual (potencialmente mutada por interceptors anteriores).
    /// - Returns: pass / transform / shortCircuit / pause.
    func intercept(_ ctx: RequestContext) async -> InterceptResult
}

/// Ordinalidad del pipeline. Un interceptor sólo corre cuando llega su phase.
///
/// Racional del orden:
/// 1. `.gate` — denegaciones tempranas (BlockList, allowlists). Evita trabajo innecesario.
/// 2. `.resolve` — respuestas sin ir a la red (Mock, MapLocal). Short-circuits frecuentes.
/// 3. `.transform` — modifica la request saliente (HeaderRewrite, Rules).
/// 4. `.network` — ajusta destino o timing antes del forward (Throttle, DNS, MapRemote).
public enum Phase: Int, Comparable, Sendable, CaseIterable {
    case gate = 0
    case resolve = 1
    case transform = 2
    case network = 3

    public static func < (lhs: Phase, rhs: Phase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Resultado de `intercept`. Define cómo continúa el pipeline.
public enum InterceptResult: Sendable {
    /// Pasar al siguiente interceptor sin cambios.
    case pass

    /// Pasar al siguiente interceptor con una versión mutada del contexto.
    /// Usado típicamente en phase `.transform` (ej. HeaderRewrite).
    case transform(RequestContext)

    /// Cortar el pipeline y responder directamente sin ir al servidor real.
    /// Usado por Mock, BlockList, MapLocal. El pipeline NO ejecuta interceptors posteriores.
    case shortCircuit(Response)

    /// Pausar la request hasta que una acción externa (típicamente UI) resuelva.
    /// La closure debe eventualmente retornar otro `InterceptResult` que indica
    /// cómo continuar (pass con ctx mutado, shortCircuit, etc.). Usado por Breakpoints.
    case pause(resolution: @Sendable () async -> InterceptResult)
}

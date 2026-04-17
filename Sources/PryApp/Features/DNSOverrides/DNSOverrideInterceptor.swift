import Foundation
import PryLib

/// Interceptor de phase `.network` que reemplaza el host de la request con una
/// IP configurada por el usuario. Corre al final de la chain, después de `.gate`,
/// `.resolve` y `.transform` — sólo si ningún short-circuit anterior respondió la
/// request.
///
/// Semánticamente mutamos el destino de la conexión: SwiftNIO acepta una IP
/// donde normalmente iría un hostname (skipea DNS resolution). Para que el
/// servidor remoto aún sepa qué vhost queremos, preservamos el domain original
/// en el header `Host`.
@available(macOS 14, *)
public struct DNSOverrideInterceptor: Interceptor {
    public let phase: Phase = .network
    private let store: DNSOverridesStore

    public init(store: DNSOverridesStore) {
        self.store = store
    }

    public func intercept(_ ctx: RequestContext) async -> InterceptResult {
        let originalHost = ctx.host
        let resolved = await MainActor.run { store.resolve(host: originalHost) }
        guard let ip = resolved else { return .pass }

        var mutated = ctx
        mutated.host = ip

        // Preservar el host original en el header `Host` para que el servidor
        // remoto sepa qué vhost servir. Si ya había un Host header, no lo
        // pisamos (probablemente puesto por un interceptor anterior con intención).
        let hasHostHeader = mutated.headers.keys.contains { $0.caseInsensitiveCompare("Host") == .orderedSame }
        if !hasHostHeader {
            mutated.headers["Host"] = originalHost
        }

        return .transform(mutated)
    }
}

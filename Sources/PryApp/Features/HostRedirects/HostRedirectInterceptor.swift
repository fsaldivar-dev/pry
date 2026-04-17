import Foundation
import PryLib

/// Interceptor de phase `.network` que redirige el destino de una request
/// cuando su host matchea una regla en `HostRedirectsStore`. Corre tarde
/// —después de `.resolve` y `.transform`— porque representa un ajuste de
/// destino antes del forward final.
///
/// Retorna `.transform(ctx)` con el host actualizado (y el header `Host`
/// sincronizado si estaba presente). No corta el pipeline: el flow sigue
/// al network layer pero apuntando al target host.
@available(macOS 14, *)
public struct HostRedirectInterceptor: Interceptor {
    public let phase: Phase = .network
    private let store: HostRedirectsStore

    public init(store: HostRedirectsStore) {
        self.store = store
    }

    public func intercept(_ ctx: RequestContext) async -> InterceptResult {
        let host = ctx.host
        let target = await MainActor.run { store.match(host: host) }
        guard let newHost = target else { return .pass }

        var mutated = ctx
        mutated.host = newHost

        // Sincronizar Host header si el cliente lo envió — case-insensitive
        // lookup, preservando la capitalización original de la key.
        if let existingKey = mutated.headers.keys.first(where: { $0.caseInsensitiveCompare("Host") == .orderedSame }) {
            mutated.headers[existingKey] = newHost
        }

        return .transform(mutated)
    }
}

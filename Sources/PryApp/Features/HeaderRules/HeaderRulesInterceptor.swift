import Foundation
import PryLib

/// Interceptor de phase `.transform` que aplica las reglas configuradas en
/// `HeaderRulesStore` sobre los headers de la request saliente. Corre después
/// del `.gate` y `.resolve` — si nadie bloqueó ni respondió sintéticamente,
/// modifica los headers antes del forward.
///
/// Usa `.transform(ctx)` — requiere propagación de transform en la chain
/// (Paso F del milestone 2).
///
/// Optimización: si las reglas no cambian los headers (store vacío o ninguna
/// regla aplica), retorna `.pass` para evitar allocar un `RequestContext` nuevo.
@available(macOS 14, *)
public struct HeaderRulesInterceptor: Interceptor {
    public let phase: Phase = .transform
    private let store: HeaderRulesStore

    public init(store: HeaderRulesStore) {
        self.store = store
    }

    public func intercept(_ ctx: RequestContext) async -> InterceptResult {
        let original = ctx.headers
        let newHeaders = await MainActor.run { store.apply(to: original) }
        if newHeaders == original {
            return .pass
        }
        var mutated = ctx
        mutated.headers = newHeaders
        return .transform(mutated)
    }
}

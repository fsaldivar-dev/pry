import Foundation
import PryLib

/// Interceptor de phase `.resolve` que responde con un status code configurable
/// cuando la request matchea algún pattern en `StatusOverridesStore`. Corre después
/// del `.gate` (Blocking) — si no lo bloqueó, quizá lo overridea.
///
/// Responde con un body JSON mínimo `{"x_pry_override":true}` para que los clientes
/// puedan distinguir overrides sintéticos de responses reales durante debugging.
@available(macOS 14, *)
public struct StatusOverrideInterceptor: Interceptor {
    public let phase: Phase = .resolve
    private let store: StatusOverridesStore

    public init(store: StatusOverridesStore) {
        self.store = store
    }

    public func intercept(_ ctx: RequestContext) async -> InterceptResult {
        let path = ctx.path
        let host = ctx.host
        let match = await MainActor.run { store.match(url: path, host: host) }
        guard let status = match else { return .pass }
        return .shortCircuit(Response(
            status: status,
            headers: ["Content-Type": "application/json"],
            body: Data(#"{"x_pry_override":true}"#.utf8)
        ))
    }
}

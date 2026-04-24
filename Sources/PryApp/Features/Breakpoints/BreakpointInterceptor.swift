import Foundation
import PryLib

/// Interceptor de phase `.gate` que pausa la request si matchea algún pattern del
/// `BreakpointsStore`. Retorna `.pause(resolution:)` — el chain espera la decisión
/// de la UI (resume / modify / cancel) y continúa con el `InterceptResult` que
/// traduce `BreakpointsStore.enqueue`.
@available(macOS 14, *)
public struct BreakpointInterceptor: Interceptor {
    public let phase: Phase = .gate
    private let store: BreakpointsStore

    public init(store: BreakpointsStore) {
        self.store = store
    }

    public func intercept(_ ctx: RequestContext) async -> InterceptResult {
        let url = ctx.path
        let host = ctx.host
        let storeRef = self.store
        let matches = await MainActor.run { storeRef.isMatch(url: url, host: host) }
        guard matches else { return .pass }
        return .pause(resolution: {
            await storeRef.enqueue(ctx: ctx)
        })
    }
}

import Foundation

/// Interceptor de phase `.gate` que responde 403 a requests cuyo host está
/// en el `BlockStore`. Corre primero en la chain — evita trabajo innecesario
/// en interceptors posteriores si la request iba a ser bloqueada de todos modos.
@available(macOS 14, *)
public struct BlockInterceptor: Interceptor {
    public let phase: Phase = .gate
    private let store: BlockStore

    public init(store: BlockStore) {
        self.store = store
    }

    public func intercept(_ ctx: RequestContext) async -> InterceptResult {
        let host = ctx.host
        let blocked = await MainActor.run { store.isBlocked(host) }
        return blocked ? .shortCircuit(.forbidden(reason: "Blocked by Pry: \(host)")) : .pass
    }
}

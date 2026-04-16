import Foundation

/// Broker pub/sub de eventos del ciclo de vida del proxy.
///
/// - Publicar: `await bus.publish(someEvent)` desde cualquier contexto.
/// - Suscribir: `for await event in bus.subscribe(to: RequestCapturedEvent.self) { ... }`.
///
/// Cada subscriber recibe su propio stream. Cancelar el `Task` que lo consume
/// desregistra automáticamente (vía `onTermination`).
///
/// Back-pressure: cada stream usa buffer con política **drop-oldest** y capacidad
/// por default de 1000 eventos. Si un consumidor es lento, se pierden los eventos
/// más viejos — el proxy nunca se bloquea por un subscriber lerdo.
public actor EventBus {
    /// Un subscriber activo: su filtro de tipo + la continuation que entrega eventos.
    private struct Subscription {
        let filter: (any PryEvent) -> (any PryEvent)?
        let yield: (any PryEvent) -> Void
    }

    private var subscriptions: [UUID: Subscription] = [:]
    private let bufferSize: Int

    /// - Parameter bufferSize: cuántos eventos retiene cada stream antes de descartar
    ///   los más viejos si el consumidor no los procesa. Default 1000.
    public init(bufferSize: Int = 1000) {
        self.bufferSize = bufferSize
    }

    /// Publica un evento a todos los subscribers interesados (filtrados por tipo).
    public func publish<E: PryEvent>(_ event: E) {
        for sub in subscriptions.values {
            if let _ = sub.filter(event) {
                sub.yield(event)
            }
        }
    }

    /// Suscribe a eventos de un tipo específico. Retorna un `AsyncStream` que
    /// termina automáticamente cuando el `Task` consumidor se cancela.
    ///
    /// Uso típico:
    /// ```swift
    /// Task {
    ///     for await event in bus.subscribe(to: RequestCapturedEvent.self) {
    ///         // reaccionar al evento
    ///     }
    /// }
    /// ```
    public nonisolated func subscribe<E: PryEvent>(to _: E.Type = E.self) -> AsyncStream<E> {
        AsyncStream<E>(bufferingPolicy: .bufferingNewest(bufferSize)) { continuation in
            let id = UUID()
            let subscription = Subscription(
                filter: { event in event is E ? event : nil },
                yield: { event in
                    if let typed = event as? E {
                        continuation.yield(typed)
                    }
                }
            )
            // Registrar la subscription dentro del actor.
            Task { await self.addSubscription(id: id, subscription: subscription) }
            // Auto-unregister cuando el stream termina (Task cancelado, deinit, etc.).
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeSubscription(id: id) }
            }
        }
    }

    private func addSubscription(id: UUID, subscription: Subscription) {
        subscriptions[id] = subscription
    }

    private func removeSubscription(id: UUID) {
        subscriptions.removeValue(forKey: id)
    }

    /// Cantidad de subscribers activos. Útil para debugging y tests.
    public var subscriberCount: Int {
        subscriptions.count
    }
}

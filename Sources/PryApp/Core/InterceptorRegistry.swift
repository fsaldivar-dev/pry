import Foundation

/// Registro thread-safe de interceptors activos.
///
/// - Features **registran** su interceptor al construirse (típicamente desde `AppCore.init`).
/// - El pipeline de proxy **pide la chain ordenada** con `chain()` antes de procesar
///   cada request.
/// - Un `register` retorna un token opaco (`UUID`) que permite `unregister` más
///   adelante. Esto habilita enable/disable en runtime sin reiniciar el proxy.
public actor InterceptorRegistry {
    private var interceptors: [UUID: any Interceptor] = [:]

    public init() {}

    /// Registra un interceptor y retorna un token para desregistrarlo después.
    @discardableResult
    public func register(_ interceptor: any Interceptor) -> UUID {
        let id = UUID()
        interceptors[id] = interceptor
        return id
    }

    /// Quita un interceptor previamente registrado. No-op si el token no existe.
    public func unregister(_ id: UUID) {
        interceptors.removeValue(forKey: id)
    }

    /// Retorna todos los interceptors actuales ordenados por `phase`.
    /// Dentro de una misma phase no se garantiza orden estable.
    public func chain() -> [any Interceptor] {
        interceptors.values.sorted { $0.phase < $1.phase }
    }

    /// Cantidad de interceptors registrados. Útil para debugging y tests.
    public var count: Int {
        interceptors.count
    }
}

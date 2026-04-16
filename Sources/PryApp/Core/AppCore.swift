import Foundation
import Observation

/// Composition root de la arquitectura nueva de PryApp (ADR-006).
///
/// Vive en `@State` en `PryApp.swift` e se inyecta al árbol de views via
/// `.environment(core)`. Cada feature accede a su store + al bus via
/// `@Environment(AppCore.self)`.
///
/// **En Paso 1 del milestone** este objeto sólo instancia `EventBus` e
/// `InterceptorRegistry`. Los stores de feature (BlockStore, MockStore, etc.)
/// se agregan en milestones posteriores según cada feature migra.
///
/// **Scope**: reemplaza progresivamente a los 6 managers legacy de PryKit
/// (`ProxyManager`, `RequestStoreWrapper`, `MockManager`, etc.). Durante la
/// migración ambos conviven — cuando una feature migra, su manager PryKit se
/// retira.
@available(macOS 14, *)
@Observable
@MainActor
public final class AppCore {
    /// Bus de eventos. Features que observan (UI, Recorder, métricas) se
    /// suscriben a tipos de eventos específicos.
    public let bus: EventBus

    /// Registro de interceptors. Features que mutan el flow se registran acá
    /// al construirse el AppCore.
    public let interceptors: InterceptorRegistry

    public init() {
        self.bus = EventBus()
        self.interceptors = InterceptorRegistry()
        // Los stores de feature se agregan en milestones siguientes.
        // Ejemplo futuro (Paso 2):
        //   self.blocks = BlockStore(bus: bus)
        //   Task { await interceptors.register(BlockInterceptor(store: blocks)) }
    }

    /// Factory para `#Preview`. Genera un `AppCore` aislado sin efectos reales.
    /// Cada feature puede proveer su propio seed via extension.
    @available(macOS 14, *)
    public static func preview() -> AppCore {
        AppCore()
    }
}

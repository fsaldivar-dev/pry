import Foundation
import Observation
import PryLib

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

    // MARK: - Feature stores

    /// Feature Blocking: lista de dominios bloqueados con matching + wildcards.
    public let blocks: BlockStore

    public init() {
        let bus = EventBus()
        self.bus = bus
        self.interceptors = InterceptorRegistry()

        // Stores de feature — AppCore concentra la dependencia a PryLib (StoragePaths)
        // y los Stores reciben el path ya resuelto. Esto cumple el layering del ADR-006:
        // ninguna feature importa PryLib directamente.
        StoragePaths.ensureRoot()
        self.blocks = BlockStore(storagePath: StoragePaths.blocksFile, bus: bus)

        // Registrar interceptors en la chain.
        let interceptors = self.interceptors
        let blocks = self.blocks
        Task { await interceptors.register(BlockInterceptor(store: blocks)) }
    }

    /// Factory para `#Preview`. Genera un `AppCore` aislado sin efectos reales.
    @available(macOS 14, *)
    public static func preview() -> AppCore {
        AppCore()
    }

    /// Factory de preview con `BlockStore` pre-poblado (útil para #Preview "with data").
    /// Usa un path temporal único para no contaminar `~/.pry/blocklist` real.
    @available(macOS 14, *)
    public static func previewWithBlockedDomains(_ domains: [String]) -> AppCore {
        let core = AppCore()
        for d in domains { core.blocks.add(d) }
        return core
    }
}

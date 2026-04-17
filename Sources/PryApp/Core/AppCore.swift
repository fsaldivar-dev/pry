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

    /// Feature StatusOverrides: responde con status codes configurables por pattern.
    public let statusOverrides: StatusOverridesStore

    /// Feature MapLocal: responde con el contenido de un archivo local cuando la
    /// URL matchea un pattern regex. Útil para reemplazar assets remotos con
    /// versiones locales durante dev.
    public let mapLocal: MapLocalStore

    /// Feature HostRedirects (MapRemote migrado): redirige requests de un host
    /// a otro a nivel .network phase via .transform.
    public let hostRedirects: HostRedirectsStore

    /// Feature HeaderRules (HeaderRewrite migrado): aplica reglas set/remove
    /// sobre headers de requests a nivel .transform phase.
    public let headerRules: HeaderRulesStore

    /// Feature DNSOverrides (DNSSpoofing migrado): resuelve dominios a IPs
    /// configurables sin ir a DNS real (phase .network).
    public let dnsOverrides: DNSOverridesStore

    /// Feature Recordings (observer pattern): subscribe al EventBus para
    /// acumular `RequestCapturedEvent` + `ResponseReceivedEvent` y guardar
    /// como `.pryrecording` en disco. No muta el flow — es observer puro.
    public let recordings: RecordingsStore

    public init() {
        let bus = EventBus()
        self.bus = bus
        self.interceptors = InterceptorRegistry()

        // Stores de feature — AppCore concentra la dependencia a PryLib (StoragePaths)
        // y los Stores reciben el path ya resuelto. Esto cumple el layering del ADR-006:
        // ninguna feature importa PryLib directamente.
        StoragePaths.ensureRoot()
        self.blocks = BlockStore(storagePath: StoragePaths.blocksFile, bus: bus)
        self.statusOverrides = StatusOverridesStore(storagePath: StoragePaths.overridesFile, bus: bus)
        self.mapLocal = MapLocalStore(storagePath: StoragePaths.mapsFile, bus: bus)
        self.hostRedirects = HostRedirectsStore(storagePath: StoragePaths.redirectsFile, bus: bus)
        self.headerRules = HeaderRulesStore(storagePath: StoragePaths.headersFile, bus: bus)
        self.dnsOverrides = DNSOverridesStore(storagePath: StoragePaths.dnsFile, bus: bus)
        self.recordings = RecordingsStore(bus: bus)

        // Registrar interceptors en la chain. Orden dentro de phase no importa —
        // la chain los corre sorted por `phase.rawValue`.
        let interceptors = self.interceptors
        let blocks = self.blocks
        let statusOverrides = self.statusOverrides
        let mapLocal = self.mapLocal
        let hostRedirects = self.hostRedirects
        let headerRules = self.headerRules
        let dnsOverrides = self.dnsOverrides
        Task {
            await interceptors.register(BlockInterceptor(store: blocks))
            await interceptors.register(StatusOverrideInterceptor(store: statusOverrides))
            await interceptors.register(MapLocalInterceptor(store: mapLocal))
            await interceptors.register(HeaderRulesInterceptor(store: headerRules))
            await interceptors.register(HostRedirectInterceptor(store: hostRedirects))
            await interceptors.register(DNSOverrideInterceptor(store: dnsOverrides))
        }
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

    /// Factory de preview con `StatusOverridesStore` pre-poblado (útil para
    /// `#Preview "with data"`). Simétrico a `previewWithBlockedDomains`.
    @available(macOS 14, *)
    public static func previewWithStatusOverrides(_ overrides: [(String, Int)]) -> AppCore {
        let core = AppCore()
        for (pattern, status) in overrides {
            core.statusOverrides.add(pattern: pattern, status: status)
        }
        return core
    }

    /// Factory de preview con `MapLocalStore` pre-poblado. Simétrico al resto.
    @available(macOS 14, *)
    public static func previewWithMapLocalMappings(_ mappings: [(String, String)]) -> AppCore {
        let core = AppCore()
        for (pattern, path) in mappings {
            core.mapLocal.add(pattern: pattern, filePath: path)
        }
        return core
    }

    /// Factory de preview con `HostRedirectsStore` pre-poblado.
    @available(macOS 14, *)
    public static func previewWithHostRedirects(_ redirects: [(String, String)]) -> AppCore {
        let core = AppCore()
        for (source, target) in redirects {
            core.hostRedirects.add(source: source, target: target)
        }
        return core
    }

    /// Factory de preview con `HeaderRulesStore` pre-poblado.
    /// Cada tupla: `(action, name, value)` — `action` es `.set` o `.remove`.
    @available(macOS 14, *)
    public static func previewWithHeaderRules(_ rules: [(HeaderRuleAction, String, String)]) -> AppCore {
        let core = AppCore()
        for (action, name, value) in rules {
            switch action {
            case .set:    core.headerRules.addSet(name: name, value: value)
            case .remove: core.headerRules.addRemove(name: name)
            }
        }
        return core
    }

    /// Factory de preview con `DNSOverridesStore` pre-poblado.
    @available(macOS 14, *)
    public static func previewWithDNSOverrides(_ overrides: [(String, String)]) -> AppCore {
        let core = AppCore()
        for (domain, ip) in overrides {
            core.dnsOverrides.add(domain: domain, ip: ip)
        }
        return core
    }
}

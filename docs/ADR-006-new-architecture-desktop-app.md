# ADR-006 — Nueva arquitectura para PryApp (macOS desktop)

- **Status**: Accepted
- **Fecha**: 2026-04-15
- **Alcance**: solo `PryApp` (GUI). `Pry` (CLI) y `PryLib/TUI` no se tocan.
- **ADRs previos** (como issues cerrados): #23 (ADR-001 SwiftUI+AppKit), #24 (ADR-002 3 capas), #25 (ADR-003 system proxy), #26 (ADR-004 distribución), #46 (ADR-005 MVVM iOS).

---

## Contexto

Tras varios meses de iteración rápida sobre PryApp, una auditoría interna detectó problemas que frenan tanto el mantenimiento como la adopción de contributors externos:

- **6 singletons** con estado mutable compartido entre event loops de NIO y `@MainActor` (`MockEngine.shared`, `Recorder.shared`, `BreakpointStore.shared`, `RequestBreakpoint.shared`, `OutputBroker.shared`, `RequestStore.shared`). Races reconocidas en comentarios del propio código (ej. `BreakpointUIManager.onPause` admite que GUI+TUI concurrentes pierden notificaciones).
- **Files monolíticos**: `UnifiedMockView.swift` (1,181 LOC), `Pry/main.swift` (1,183 LOC) bloquean cualquier cambio simple.
- **Layering violado**: 66% de las views de `PryApp` importan `PryLib` directo en vez de ir por `PryKit`. Cambiar un tipo en PryLib implica tocar views.
- **DI ausente**: todo es concreto e instanciado a `@State` en `PryApp.swift:11-16`. Imposible mockear para tests o previews. **Cero `#Preview`** en 38 archivos de view.
- **Reactivity imperativa**: managers llaman `reload()` manual tras mutar, sin publishers/streams. El callback único de breakpoints sólo admite un subscriber (GUI o TUI, no ambos).
- **Tests dependen del filesystem real** (`~/.pry/`) — riesgo de flakiness.

Agregar una feature nueva toca ~5 archivos en 3 módulos, y cada feature adicional amplifica los problemas. La barrera para contribuir es alta, y para el mantenedor individual ya empieza a ser friccional.

---

## Decisión

Diseñar e introducir una arquitectura nueva **solo en `PryApp`**, basada en tres conceptos minimalistas y ortogonales. CLI/TUI se quedan como están.

### 1. Interceptor chain

Un protocolo único que describe cómo cada feature puede **mutar el flow** del proxy. Ejecución ordenada por `phase`:

```swift
protocol Interceptor: Sendable {
    var phase: Phase { get }
    func intercept(_ ctx: RequestContext) async -> InterceptResult
}

enum Phase: Int, Comparable {
    case gate = 0        // BlockList, allowlists
    case resolve = 1     // Mock, MapLocal (short-circuit antes de la red)
    case transform = 2   // HeaderRewrite, Rules (muta request saliente)
    case network = 3     // Throttle, DNSSpoofing, MapRemote (modifica destino o timing)
}

enum InterceptResult {
    case pass
    case transform(RequestContext)
    case shortCircuit(Response)
    case pause(resolution: () async -> InterceptResult)
}
```

Cada feature que muta el flow se implementa como un `struct` conforme a `Interceptor`. La `InterceptorRegistry` (un `actor`) mantiene el orden y permite `register`/`unregister` en runtime (enable/disable sin reiniciar).

### 2. EventBus (observers via AsyncStream)

Un `actor EventBus` que publica eventos del ciclo de vida del proxy (`RequestCaptured`, `ResponseReceived`, `RequestPaused`, `TrafficCleared`, `TunnelOpened`, etc.). Cualquier cantidad de subscribers consume via `AsyncStream`:

```swift
let stream = core.bus.subscribe()
for await event in stream {
    // UI, recorder, métricas, TUI externa... cada uno su copia
}
```

- **Zero callbacks únicos**: N subscribers simultáneos sin pisarse.
- **Subscribe/unsubscribe natural**: cancelar el `Task` termina el stream y limpia recursos.
- **Buffered + drop-oldest** por default — el proxy nunca se bloquea si un consumer es lento.
- **Body lazy**: eventos llevan `id + headers`. El body se pide on-demand via referencia, evitando copias innecesarias.

Los observers **no pueden mutar** el flow. Si una feature necesita mutar → es un Interceptor. Si sólo observa → suscribe al bus. Esa separación es invariante.

### 3. Feature store (`@Observable @MainActor`)

Cada feature encapsula su state + persistence + actions en un único objeto:

```swift
@Observable @MainActor
final class BlockStore {
    var domains: [String]
    private let bus: EventBus
    // add/remove/clear/isBlocked + persist
}
```

- **Combina repo + viewmodel**: evita capas de wrapping innecesarias.
- **Inyectado via `@Environment`** a las views.
- **Previews triviales**: una factory que retorna un store con data fake.
- **Suscribe al bus** si necesita eventos.
- **Interceptors leen del store** via `MainActor.run` cuando corren en NIO thread (1 línea).

### Composition root

`PryApp.swift` instancia un solo objeto `AppCore` (`@Observable @MainActor`) que arma `bus`, `interceptors`, y las stores. Lo inyecta via `.environment(core)`. Las features acceden via `@Environment(AppCore.self)`.

### Organización física

```
Sources/PryApp/
├── Core/                    # protocolos + bus + AppCore + Events
├── Features/
│   ├── Blocking/            # BlockStore + BlockInterceptor + BlocksView
│   ├── Mocking/             # MockStore + MockInterceptor + MocksView
│   └── ...                  # un folder por feature, 2-3 archivos
├── Shared/                  # componentes reutilizables
└── PryApp.swift             # @main
```

Una feature completa = un folder con ~3 archivos de ~100 LOC. Template copiable, trivial para IA y contributors.

---

## Coexistencia con el código viejo

**CLI/TUI intocables.** Siguen usando `BlockList.shared`, `MockEngine.shared`, etc. Siguen imprimiendo a `OutputBroker.shared.log`.

**Filesystem como contrato**: los nuevos stores escriben a los **mismos archivos** en `~/.pry/` que los legacy (via `StoragePaths`). CLI y GUI leen la misma data. Nunca corren simultáneamente (el proxy escucha en el mismo puerto), así que no hay carrera de runtime.

**Estrategia**: strangler fig. Se agrega la arquitectura nueva al lado del código viejo. Se migra una feature por vez. Durante meses PryApp queda "híbrida" (parte vieja, parte nueva) — aceptable y deseable, porque cada PR es chico y revertible.

Cuando todas las features migran, los singletons originales quedan sin consumers dentro de PryApp y se pueden deprecar (no eliminar — CLI sigue usándolos).

---

## Consecuencias

### Ganancias

- **Testabilidad**: stores y interceptors testeables con fakes. Views testeables con previews.
- **Contributor-friendliness**: agregar feature = copiar folder, modificar 3 archivos. Documentable en CONTRIBUTING.md con ejemplo concreto.
- **Zero races**: actors isolated + MainActor stores + AsyncStream. `@unchecked Sendable` desaparece de código nuevo.
- **Observabilidad**: múltiples subscribers del bus (UI + futura telemetría + export + whatever) sin pisarse.
- **Features aisladas**: un bug en mocking no toca blocking. Interceptor A no conoce interceptor B.
- **Enable/disable en runtime**: registry permite prender/apagar features sin reiniciar el proxy.

### Trade-offs

- **Fase híbrida larga**: durante la migración PryApp tiene dos patrones coexistiendo. Mitigación: cada PR entrega una feature migrada, nunca se bloquea la app.
- **`@MainActor` stores**: interceptors en NIO thread necesitan `await MainActor.run { store.method() }` para leer. Una línea extra, costo ínfimo.
- **Curva de entrada**: contributors nuevos deben entender `actor`, `AsyncStream`, `@Observable`. Mitigación: template + ejemplo + CONTRIBUTING.md reducen esto a 30 min de lectura.
- **Más archivos por feature**: 3 chicos en vez de 1 mediano. Net positivo para mantenibilidad; neutro para navegación.

### Explícitamente fuera de scope

- **CLI** (`Sources/Pry/main.swift`) — no se toca en esta refactorización.
- **TUI** (`Sources/PryLib/TUI/`) — no se toca.
- **Network Extension** (issue #86) — ortogonal, se beneficia de esta arquitectura cuando llegue pero no es prerequisito.
- **Cambios en `Package.swift`** — se mantienen los 4 targets actuales. Nada de módulos SPM por feature.
- **Dependencias externas** — se mantiene la filosofía "Swift puro + NIO".

---

## Plan de rollout

### Milestone 1 — Bases (cubierto por este PR + dos más)

1. **Paso 0** (este PR): este ADR como documentación.
2. **Paso 1**: scaffolding de `Sources/PryApp/Core/` con los protocolos + `EventBus` + `AppCore` vacío. Sin conectar al flujo actual. Código nuevo inerte.
3. **Paso 2**: migrar `BlockList` (45 LOC, la más simple) como proof-of-concept. Se crea `Sources/PryApp/Features/Blocking/` con `BlockStore` + `BlockInterceptor` + `BlocksView` + tests + previews. El pipeline real del proxy todavía usa el legacy `BlockList.isBlocked` — sólo la GUI empieza a usar el path nuevo.

### Milestone 2

4. Integrar la `InterceptorRegistry` en `HTTPInterceptor` y `ConnectHandler` (reemplaza call sites legacy de `BlockList` por la chain nueva).
5. Migrar `MapRemote` siguiendo el template validado.
6. Documentar el proceso en `CONTRIBUTING.md` con ejemplo paso a paso.

### Milestone 3+ (un PR por feature)

7. `DNSSpoofing` → `Features/DNSOverrides/`
8. `StatusOverrideStore` → `Features/StatusOverrides/`
9. `HeaderRewrite` → `Features/HeaderRules/`
10. `Recorder` → `Features/Recordings/`
11. `Breakpoints` → `Features/Breakpoints/` (con `BreakpointCoordinator` actor para manejar pausa/resume con continuations)
12. `Mocking` → `Features/Mocking/` (el más grande, al final, con aprendizaje acumulado)

Cada paso es un PR merged antes del siguiente. Revertible individualmente.

---

## Referencias

- [Auditoría interna](../.claude/plans/parallel-sniffing-seal.md) (histórica — será reemplazada por otros planes)
- Issues relacionados: #73 (Background Service), #84 (Watchdog), #86 (Network Extension) — todos compatibles con esta arquitectura
- [Apple: `@Observable`](https://developer.apple.com/documentation/Observation)
- [Swift concurrency proposal SE-0306 (Actors)](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md)

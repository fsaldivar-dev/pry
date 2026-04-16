# Arquitectura de Pry — Snapshot actual

Este documento es el **mapa vivo** del proyecto: muestra el estado de la arquitectura al día de hoy, cómo convive la capa legacy con la nueva, y cómo entran las features nuevas.

Para **entender por qué** se tomaron las decisiones actuales, leer [ADR-006](./ADR-006-new-architecture-desktop-app.md). Este doc es el **"qué existe hoy"**, el ADR es el **"por qué"**.

---

## 1. Grafo de módulos

```
PryApp (GUI, executableTarget, macOS-only)
    │
    └── depends on ──▶ PryKit (library, macOS-only)
                          │
                          └── depends on ──▶ PryLib (library, cross-platform)
                                                │
                                                └── depends on ──▶ swift-nio + swift-nio-ssl + swift-certificates

Pry (CLI, executableTarget)
    │
    └── depends on ──▶ PryLib
```

| Target | Rol | LOC aprox |
|---|---|---|
| `PryLib` | Kernel del proxy: NIO handlers, CA, storage, stores legacy con singletons | ~7,600 |
| `PryKit` | Managers @Observable @MainActor que puentean PryLib a SwiftUI | ~500 |
| `PryApp` | GUI SwiftUI para macOS | ~4,400 |
| `Pry` | CLI | ~1,200 |

**Regla**: PryLib nunca importa SwiftUI/AppKit. Cross-platform por diseño.

---

## 2. Estado de la migración arquitectónica

La GUI (PryApp) está **en transición** entre dos arquitecturas. Ver [ADR-006](./ADR-006-new-architecture-desktop-app.md) para el racional.

```
┌─────────────────────────────────────────────────────────────────┐
│                        PryApp (GUI)                             │
│                                                                 │
│  ┌───────────────────────────┐  ┌───────────────────────────┐   │
│  │  NUEVO (Core + Features/) │  │  LEGACY (Views/)          │   │
│  │                           │  │                           │   │
│  │  Sources/PryApp/          │  │  Sources/PryApp/Views/    │   │
│  │  ├─ Core/                 │  │  ├─ UnifiedMockView       │   │
│  │  │  ├─ Interceptor        │  │  ├─ RequestListView       │   │
│  │  │  ├─ InterceptorRegistry│  │  ├─ MainWindow            │   │
│  │  │  ├─ EventBus           │  │  ├─ BreakpointListView    │   │
│  │  │  ├─ Events             │  │  └─ ... (33 files)        │   │
│  │  │  ├─ RequestContext     │  │                           │   │
│  │  │  ├─ Response           │  │  Consume via @Environment │   │
│  │  │  └─ AppCore            │  │  los 6 managers PryKit    │   │
│  │  │                        │  │                           │   │
│  │  └─ Features/             │  │                           │   │
│  │     ├─ Blocking/  ◀──── primer feature migrada (PR WIP)  │   │
│  │     └─ ...                │  │                           │   │
│  │                           │  │                           │   │
│  │  Reglas nuevas:           │  │  Reglas viejas:           │   │
│  │  • Protocol Interceptor   │  │  • Singletons .shared     │   │
│  │  • EventBus pub/sub       │  │  • Callback único         │   │
│  │  • @Observable stores     │  │  • @Observable managers   │   │
│  │  • Zero singletons nuevos │  │  • Import directo a       │   │
│  │  • Tests TDD-first        │  │    PryLib (bypass PryKit) │   │
│  └───────────────────────────┘  └───────────────────────────┘   │
│              │                              │                   │
└──────────────┼──────────────────────────────┼───────────────────┘
               │                              │
               └──────────┬───────────────────┘
                          ▼
              ┌───────────────────────┐
              │         PryKit        │
              │  6 managers legacy    │
              │  (@Observable wraps)  │
              └───────────┬───────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │         PryLib        │
              │                       │
              │  Singletons vivos:    │
              │  • MockEngine         │
              │  • Recorder           │
              │  • BreakpointStore    │
              │  • RequestStore       │
              │  • OutputBroker       │
              │  • RequestBreakpoint  │
              │                       │
              │  + NIO pipeline       │
              │  + CA                 │
              │  + StoragePaths       │
              └───────────┬───────────┘
                          │
       ┌──────────────────┼──────────────────┐
       ▼                  ▼                  ▼
   ┌────────┐        ┌─────────┐        ┌──────────┐
   │  Pry   │        │   TUI   │        │ ~/.pry/  │
   │ (CLI)  │        │         │        │  files   │
   └────────┘        └─────────┘        └──────────┘
    intocable         intocable         shared state
```

**Progresión**:
- Legacy Views/ **se achica** a medida que cada feature migra a Features/
- PryKit managers se retiran uno a uno cuando su feature equivalente migra
- CLI y TUI nunca migran — siguen usando singletons para siempre

---

## 3. Flujo de datos en la arquitectura nueva

Dos caminos ortogonales nacen del mismo stream de requests del proxy:

```
  HTTP(S) request
        │
        ▼
   NIO pipeline
        │
        ▼
   ProxyKernel ──────────────┐
        │                    │
        ▼                    ▼
  InterceptorChain      EventBus
  (muta el flow)      (observa, no muta)
        │                    │
   ┌────┼────┐        ┌──────┼──────┐
   ▼    ▼    ▼        ▼      ▼      ▼
  gate resolve transform    UI  Recorder  TUI
   │    │    │            store  future   ...
   │    │    │            @Observable
   ▼    ▼    ▼
   Block Mock Header
        MapLocal Rewrite
              │
              ▼
  Response / pass / shortCircuit / pause
        │
        └──▶ publish ResponseReceivedEvent (observers reaccionan)
```

| Concepto | Qué es | Cómo se implementa |
|---|---|---|
| **Interceptor** | Muta el flow del proxy | `protocol Interceptor` con `phase` + `intercept() async -> InterceptResult` |
| **Phase** | Orden de ejecución | `gate` (0) → `resolve` (1) → `transform` (2) → `network` (3) |
| **InterceptResult** | Qué hacer con la request | `.pass` / `.transform(ctx)` / `.shortCircuit(response)` / `.pause(resolution:)` |
| **EventBus** | Pub/sub de eventos de ciclo de vida | `actor EventBus` con `AsyncStream<E>` por subscriber |
| **FeatureStore** | State + repo + viewmodel en uno | `@Observable @MainActor final class XStore` |

---

## 4. Cómo se ve una feature nueva (target)

Cada feature es un folder con 3 archivos + tests:

```
Sources/PryApp/Features/Blocking/
├── BlockStore.swift          @Observable @MainActor — state, load/save, actions
├── BlockInterceptor.swift    Interceptor — muta el flow (phase: .gate)
└── BlocksView.swift          SwiftUI — consume AppCore via @Environment

Tests/PryAppTests/Features/Blocking/
├── BlockStoreTests.swift      unit tests, fakes, temp dirs (no ~/.pry/ real)
└── BlockInterceptorTests.swift  branches pass / shortCircuit / transform
```

Se registran en `AppCore.init`:

```swift
self.blocks = BlockStore(bus: bus)
Task { await interceptors.register(BlockInterceptor(store: blocks)) }
```

La view consume:

```swift
struct BlocksView: View {
    @Environment(AppCore.self) var core
    var body: some View { /* core.blocks.domains, core.blocks.add, etc. */ }
}
```

---

## 5. Workflow de desarrollo (features nuevas)

Tooling en `.claude/`:

```
/new-feature Blocking                       ← scaffoldea folder en RED (tests fallan)
                 │
                 ▼
            editar hasta GREEN (swift test pasa)
                 │
                 ▼
/tdd isBlocked supports wildcards           ← ciclo RED-GREEN-REFACTOR
                 │
                 ▼
Agent({ subagent_type: "arch-reviewer" })   ← valida 10 reglas del ADR-006
                 │
                 ▼
           commit → push → PR → merge
```

Documentación de cada tool:
- `.claude/skills/new-feature/SKILL.md` — scaffolding TDD-first
- `.claude/skills/tdd/SKILL.md` — pair programming RED-GREEN-REFACTOR
- `.claude/agents/arch-reviewer.md` — validación automática pre-PR

Reglas clave en CLAUDE.md:
- TDD obligatorio en `Sources/PryApp/Features/`
- Tests **nunca** tocan `~/.pry/` real — usan temp dirs y fakes
- Zero singletons nuevos
- CLI y TUI están **congelados** (no se tocan)

---

## 6. Coexistencia GUI ↔ CLI/TUI

Ambos binarios comparten `~/.pry/` como única superficie común. Nunca corren simultáneamente (pelean por el puerto 8080).

```
~/.pry/
├── config              Config key=value (port, filter)
├── watch               watchlist (dominios HTTPS a interceptar)
├── mocks               legacy mocks (key=value, CLI-compatible)
├── blocks              dominios bloqueados
├── redirects           map remote (host → host)
├── dns                 DNS overrides (host → IP)
├── overrides           status code overrides
├── headers             header rewrite rules
├── ca/                 CA cert + key
├── projects/           proyectos con scenarios + mocks
├── scenarios/          scenarios legacy
├── recordings/         grabaciones de tráfico
└── pry.log             log histórico
```

Cuando una feature migra en PryApp, sus stores nuevos **leen/escriben los mismos archivos** que los stores legacy. El CLI sigue funcionando con su singleton viejo y ve los mismos datos.

---

## 7. Scorecard actual

| Dimensión | Hoy | Target (cuando todas las features migraron) |
|---|---|---|
| Layering limpio PryApp ↔ PryKit ↔ PryLib | C (66% views saltan) | A |
| Zero singletons en código nuevo | En progreso | A |
| Tests TDD-first en features | A (enforced via tooling) | A |
| Races en state compartido | B- (@unchecked Sendable vivo) | A |
| Doc coverage público | ~5% | >30% |
| Previews en views | 0 | ≥1 por feature |
| Feature-based folder organization | En progreso | A |

---

## Referencias

- [ADR-006 — Nueva arquitectura](./ADR-006-new-architecture-desktop-app.md)
- [CLAUDE.md](../CLAUDE.md) — reglas + filosofía del proyecto
- `.claude/skills/` — slash commands para scaffolding y TDD
- `.claude/agents/arch-reviewer.md` — review automático

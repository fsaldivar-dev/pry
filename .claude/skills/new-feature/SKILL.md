---
name: new-feature
description: Scaffold a new PryApp feature following the ADR-006 architecture (Store + Interceptor + View) with TDD-first tests
---

# /new-feature — Scaffold a feature (TDD-first)

## Visión

Cada feature de PryApp sigue el patrón establecido en [ADR-006](../../../docs/ADR-006-new-architecture-desktop-app.md): un folder con 3 archivos (`Store`, `Interceptor`, `View`) más sus tests. Este skill automatiza la creación respetando la disciplina **TDD obligatoria**: tests primero, código después.

## Cuándo usar

- Migrar una feature legacy de `PryLib/*.swift` al nuevo patrón
- Agregar una feature completamente nueva
- Ejemplos válidos: Blocking, MapRemote, DNSOverrides, HeaderRules, Throttling, Mocking, Breakpoints

## Cuándo NO usar

- Cambios puntuales dentro de una feature existente → usa `/tdd` en su lugar
- Features que no mutan el flow Y no tienen UI (ej. utility puro) → no aplica este patrón

## Entrada que necesito del usuario

Antes de generar archivos, preguntarle al usuario:

1. **Nombre de la feature** (PascalCase, ej. `Blocking`, `MapRemote`)
2. **¿Qué hace el Interceptor?** (uno de):
   - `gate` — bloquea o deja pasar (BlockList, allowlist)
   - `resolve` — reemplaza la response (Mock, MapLocal)
   - `transform` — modifica request/response (HeaderRewrite, Rules)
   - `network` — cambia destino/timing (Throttle, DNS)
   - `none` — feature solo observa, no muta (sólo tiene Store + View, sin Interceptor)
3. **¿Qué comportamiento clave del Store quiero testear?** (lista de 2-4 behaviors, ej. "add domain, remove domain, isBlocked matches wildcard, persists across reload")
4. **¿Qué branches del Interceptor testear?** (pass, shortCircuit, transform, pause)

## Qué genero

### 1. Tests PRIMERO (RED)

Crear archivos en orden, con asserts reales que fallarán al correr:

```
Tests/PryAppTests/Features/{Name}/
├── {Name}StoreTests.swift
└── {Name}InterceptorTests.swift   (si aplica)
```

Cada test usa fakes (`InMemoryEventBus`, `TempDirFileStorage`), nunca toca `~/.pry/` real. Cada test tiene `XCTAssertEqual` o `#expect` con valores esperados concretos — no `XCTAssertTrue(true)` placeholders.

### 2. Implementación stub (mantiene RED)

Crear archivos con stubs que hagan fallar los tests por **assertion**, no por compile:

```
Sources/PryApp/Features/{Name}/
├── {Name}Store.swift         — propiedades + métodos con fatalError("TODO RED")
├── {Name}Interceptor.swift   — intercept() retorna .pass con fatalError comentado
└── {Name}View.swift          — SwiftUI mínimo que compila + #Preview con fake store
```

### 3. Registro en AppCore

Agregar al final de `Sources/PryApp/Core/AppCore.swift` init:
- Instanciar el Store
- Registrar el Interceptor en `interceptors` (si aplica)

### 4. Verificar RED

Correr:
```bash
swift test --filter {Name}
```

Mostrar al usuario la salida: debe aparecer al menos 1 test FAIL. Ese es el punto de partida correcto del ciclo TDD.

## Convenciones específicas del template

### {Name}Store.swift

```swift
import Foundation

@Observable @MainActor
public final class {Name}Store {
    // MARK: - State
    public private(set) var items: [{ItemType}] = []

    // MARK: - Dependencies
    private let storagePath: String
    private let bus: EventBus

    // MARK: - Init
    public init(storagePath: String = StoragePaths.{someFile}, bus: EventBus) {
        self.storagePath = storagePath
        self.bus = bus
        reload()
    }

    // MARK: - Actions
    public func add(_ item: {ItemType}) {
        fatalError("TODO RED: implement add")
    }

    // ... more methods as RED stubs

    // MARK: - Persistence
    private func reload() {
        // leer de storagePath
    }

    private func persist() {
        // escribir a storagePath
    }
}
```

### {Name}Interceptor.swift

```swift
import Foundation

public struct {Name}Interceptor: Interceptor {
    public let phase: Phase = .{gateOrResolveOrTransformOrNetwork}
    private let store: {Name}Store

    public init(store: {Name}Store) {
        self.store = store
    }

    public func intercept(_ ctx: RequestContext) async -> InterceptResult {
        fatalError("TODO RED: implement intercept logic")
    }
}
```

### {Name}View.swift

```swift
import SwiftUI

struct {Name}View: View {
    @Environment(AppCore.self) private var core

    var body: some View {
        Text("{Name} — TODO")
    }
}

#Preview("empty") {
    {Name}View()
        .environment(AppCore.preview())
}

#Preview("with data") {
    {Name}View()
        .environment(AppCore.preview(seed: .{name}Sample))
}
```

### {Name}StoreTests.swift

Un `XCTestCase` por cada behavior que pidió el usuario. Usar fakes. Setup/teardown con temp dir.

```swift
import XCTest
@testable import PryApp

final class {Name}StoreTests: XCTestCase {
    var store: {Name}Store!
    var bus: EventBus!
    var tempDir: URL!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bus = EventBus()
        store = await {Name}Store(
            storagePath: tempDir.appendingPathComponent("store").path,
            bus: bus
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    @MainActor
    func test_add_appendsToItems() throws {
        // GIVEN
        XCTAssertTrue(store.items.isEmpty)
        // WHEN
        store.add(.sample)
        // THEN — deliberadamente falla hasta implementar add()
        XCTAssertEqual(store.items.count, 1)
    }

    // ... más tests por cada behavior
}
```

### {Name}InterceptorTests.swift

```swift
import XCTest
@testable import PryApp

final class {Name}InterceptorTests: XCTestCase {
    func test_phase_is{Expected}() {
        let store = {Name}Store(/* fakes */)
        let sut = {Name}Interceptor(store: store)
        XCTAssertEqual(sut.phase, .{expected})
    }

    func test_pass_when{Condition}() async {
        // arrange, act, assert
    }

    func test_shortCircuit_when{Condition}() async {
        // ...
    }
}
```

## Después del scaffold

Al usuario le decís:

1. "Tests corren en RED — mostrame la salida para verificar"
2. "Implementá método por método, corriendo `swift test --filter {Name}` entre cada uno"
3. "Cuando todo esté GREEN, corré `Agent({ subagent_type: 'arch-reviewer' })` antes del PR"

## Archivos a leer para tener contexto

Antes de generar, leer (si existen):
- `docs/ADR-006-new-architecture-desktop-app.md` — la fuente de verdad del patrón
- `Sources/PryApp/Core/Interceptor.swift` — protocolo a implementar
- `Sources/PryApp/Core/AppCore.swift` — para saber dónde registrar
- `Sources/PryApp/Features/Blocking/` — si existe, es el template validado de referencia
- `Sources/PryLib/StoragePaths.swift` — para elegir/agregar el path correcto

Si alguno no existe (ej. todavía estamos en Paso 1 del milestone y no se creó Core/), avisar al usuario que es prerequisito.

## Principios no negociables

- Tests van PRIMERO en el commit (diff muestra el test file antes que el impl file)
- Nunca tocar `~/.pry/` real en tests — siempre temp dir
- Stubs usan `fatalError("TODO RED: ...")`, nunca devuelven valores falsos que hagan pasar los tests
- Todo archivo nuevo tiene doc comment (`///`) en la declaración pública
- `Sources/PryApp/Core/` existe antes de correr este skill — si no, abortar y pedirle al usuario que primero arme el scaffolding del Paso 1

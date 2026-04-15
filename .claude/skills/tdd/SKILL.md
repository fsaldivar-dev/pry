---
name: tdd
description: Pair programming TDD cycle (RED → GREEN → REFACTOR) para cambios dentro de una feature existente de PryApp
---

# /tdd — Pair programming TDD dentro de una feature

## Visión

Cuando ya hay una feature armada con `/new-feature` y querés **agregar un comportamiento nuevo** (o arreglar un bug, o refactorizar), este skill conduce el ciclo RED-GREEN-REFACTOR de forma explícita.

La diferencia con `/new-feature`: este no crea archivos. Edita los existentes siguiendo el ciclo.

## Cuándo usar

- Agregar un método nuevo a un Store existente
- Agregar una rama nueva en un Interceptor existente
- Arreglar un bug (regression test primero, fix después)
- Refactor con seguridad (tests pasan antes y después)

## Cuándo NO usar

- Crear una feature nueva desde cero → usa `/new-feature`
- Cambios puramente cosméticos en la UI (renombre de texto, color) → directo sin TDD
- Cambios en archivos de documentación → no aplica

## Entrada del usuario

`/tdd <qué querés hacer>` — ej. `/tdd BlockStore soporta wildcards con *.example.com`

Si el mensaje es vago, preguntar:
- ¿En qué archivo? (Store, Interceptor, View, o varios)
- ¿Qué comportamiento nuevo esperás? (describilo como test: "dado X, cuando Y, entonces Z")
- ¿Rompe algún test existente? Si sí, ¿hay que actualizarlo o es regresión?

## Ciclo

### 1. RED — escribir el test primero

Editar el archivo de tests correspondiente. Agregar **un solo test** que exprese el comportamiento nuevo. Asserts reales, no placeholders.

```swift
func test_isBlocked_withWildcardPattern_matchesSubdomain() {
    // GIVEN
    store.add("*.example.com")
    // WHEN
    let result = store.isBlocked("api.example.com")
    // THEN
    XCTAssertTrue(result)
}
```

Correr el test:
```bash
swift test --filter <TestClass>/<testMethod>
```

**Esperar**: FAIL. Si pasa de entrada, el test está mal (no prueba nada nuevo) — mostrar al usuario y replantear.

Mostrar la salida al usuario y decir: "✓ RED confirmado. Listo para implementar?"

### 2. GREEN — implementación mínima

Editar el archivo de producción. Implementar **lo mínimo** para que el test pase. No agregar features adicionales. No optimizar todavía.

Correr el test:
```bash
swift test --filter <TestClass>/<testMethod>
```

**Esperar**: PASS. Correr también toda la suite de la feature para confirmar que no rompimos nada:
```bash
swift test --filter <FeatureName>
```

Si algún test existente rompió, parar y analizar con el usuario antes de continuar.

Mostrar salida: "✓ GREEN. ¿Refactorizamos o seguimos con otro test?"

### 3. REFACTOR — mejorar con red de seguridad

Preguntar al usuario: "¿Ves algo para mejorar en el código nuevo o existente? Si querés, revisaré yo."

Si hay refactor claro (extraer función, renombrar, eliminar duplicación), proponerlo como diff. Después de cada refactor:
```bash
swift test --filter <FeatureName>
```

Tests deben seguir GREEN. Si no, revertir.

## Reglas

- **Un test a la vez**. No generar 5 tests de golpe. Cycle uno por uno.
- **El test siempre se commitea antes de la implementación** si el usuario hace commits granulares. Para un commit único, orden dentro del diff: test file primero.
- **Nunca** escribir código que no responda a un test fallado.
- **Siempre** correr `swift test` para confirmar transiciones. No asumir.
- **Nunca** tocar `~/.pry/` real en tests. Usar temp dirs y fakes.

## Salida típica al usuario

```
[RED]
swift test --filter BlockStoreTests/test_isBlocked_withWildcardPattern_matchesSubdomain
→ Test Case '-[BlockStoreTests test_isBlocked_withWildcardPattern_matchesSubdomain]' failed
  XCTAssertTrue failed - 0 != 1

✓ Confirmado en RED. Implemento `isBlocked` para soportar wildcards?

[GREEN]
swift test --filter BlockStore
→ Test Suite 'BlockStoreTests' passed

✓ GREEN (8/8 tests pasan). ¿Refactor o seguimos con el siguiente behavior?
```

## Archivos a leer para contexto

- El archivo de la feature que se va a modificar (`Sources/PryApp/Features/{X}/`)
- Los tests existentes de esa feature (`Tests/PryAppTests/Features/{X}/`)
- `docs/ADR-006-new-architecture-desktop-app.md` solo si el cambio involucra el patrón Interceptor/EventBus

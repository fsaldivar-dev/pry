# Pry — Bitácora de Desarrollo

## Sesión 2026-04-02

### Objetivo
Crear un proxy HTTP CLI en Swift con SwiftNIO. Alternativa open source a Proxyman.

### v0.1: HTTP Proxy

**Resultado:** Funcional. HTTP forwarding + mocking + logging.

**Lo que se construyó:**
- `ProxyServer`: ServerBootstrap con SwiftNIO, bind en 0.0.0.0:8080
- `HTTPInterceptor`: ChannelInboundHandler que captura HEAD + BODY, logea a stdout y /tmp/pry.log
- `MockHandler`: integrado en HTTPInterceptor, matchea path contra mocks registrados
- `Config`: .pryconfig key=value, mismo patrón que AutoPilot (.autopilot)
- Command dispatch: switch en main.swift con guard para args, mismo patrón que AutoPilot

**Verificado con:**
```bash
curl -x http://localhost:8080 http://httpbin.org/get     # Forward OK
pry mock /api/test '{"hello":"world"}'
curl -x http://localhost:8080 http://anything/api/test    # Mock OK
pry log                                                   # Log OK
```

**Problemas encontrados:**
- NIOAny deprecated warnings al hacer write/writeAndFlush — SwiftNIO 2.97 quiere que evites NIOAny wrapping
- El binary name `pry` coincide con un gem de Ruby (pry REPL) — no es conflicto en nuestro contexto

---

### v0.2: HTTPS Infrastructure

**Resultado:** Parcial. Infraestructura lista, tunneling y interception WIP.

**Lo que se construyó:**
- `CertificateAuthority`: genera CA cert con swift-certificates (P256, ECDSA), guarda en ~/.pry/ca/
- `Watchlist`: .prywatch archivo, add/remove/list, soporta wildcards (*.myapp.io)
- `ConnectHandler`: state machine para método CONNECT (patrón de apple/swift-nio-examples)
- `GlueHandler`: bidirectional byte forwarding para túnel CONNECT
- `TLSForwarder`: handler para requests descifrados post-MITM
- Comandos: add, remove, list, trust, ca

**Lo que funciona:**
- CA certificate se genera correctamente (PEM 64-char lines, P256)
- Watchlist add/remove/list/matches con wildcards
- `pry trust` ejecuta `xcrun simctl keychain booted add-root-cert`
- ConnectHandler detecta CONNECT, decide tunnel vs intercept
- Logging de TUNNEL y INTERCEPT

**Lo que NO funciona:**
- HTTPS tunneling: GlueHandler se instala pero los bytes no fluyen entre client y remote
  - Probé 4 implementaciones de GlueHandler: pair con partnerContext, simple con peerChannel, con autoRead, Apple's exact pattern
  - El CONNECT 200 se envía correctamente (curl lo ve)
  - Los bytes TLS post-200 no llegan al channelRead del GlueHandler
  - Sospecha: el pipeline no está completamente limpio después de remover HTTP handlers, o hay un issue con syncOperations vs async removal
- HTTPS interception: cert se genera pero el handshake no completa
  - El pipeline MITM (NIOSSLServerHandler → HTTPDecoder → TLSForwarder) se instala sin errores
  - Pero no hay output — el client no recibe response

**Aprendizaje clave:**
- `HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)` es CRÍTICO — sin esto los bytes TLS post-CONNECT se parsean como HTTP y crashean con fatal error
- `syncOperations` para remover handlers es necesario — si usas async, los bytes TLS llegan antes de que se remuevan los HTTP handlers
- El patrón de Apple (swift-nio-examples/connect-proxy) usa una state machine de 6 estados para manejar las race conditions entre CONNECT request completion y peer connection

**Error memorable:**
- `.build/` de 314MB se coló en un git commit → GitHub rechazó push por archivo de 256MB → hubo que hacer filter-branch para limpiar toda la historia

---

## Sesión 2026-04-03

### Objetivo
CI/CD, branch protection, documentación como libro técnico.

**Lo que se hizo:**
- CI workflow: build + release build en macos-14
- Release workflow: semantic versioning via PR labels (major/minor/patch)
- Branch protection en main: requiere status check build-and-test + PR
- CLAUDE.md: guía de desarrollo
- /docs skill: documentación como libro técnico
- Libro: índice + Capítulo 1 (El problema)
- Bitácora: este archivo

**Problema encontrado:**
- `swift test` falla si no hay test target → quitado del CI por ahora
- Tests requieren separar en library + executable target (PryLib + Pry) → pendiente para cuando haya tests reales

---

### Los bytes no fluyen — la cacería del bug HTTPS

Llevábamos 4 implementaciones de GlueHandler. Todas compilaban. Ninguna funcionaba. El CONNECT 200 se enviaba perfecto — curl lo veía, establecía el túnel — pero después: silencio. Los bytes TLS del ClientHello entraban al proxy y desaparecían. Sin error, sin crash, sin log. Nada.

Probamos de todo:
- GlueHandler con `matchedPair()` y `partnerContext` → silencio
- GlueHandler simplificado con `peerChannel` directo → silencio
- Forzar `autoRead = true` en ambos canales → silencio
- Copiar exacto el GlueHandler de Apple → silencio

El GlueHandler no era el problema. Los bytes nunca llegaban a él.

### La investigación

Buscamos en Swift Forums, GitHub issues de swift-nio, y clonamos el connect-proxy de Apple para comparar línea por línea. La comparación fue brutal — nuestro ConnectHandler se veía casi idéntico al de Apple. Casi.

El de Apple tenía esta transición:
```swift
case .beganConnecting:
    if case .end = self.unwrapInboundIn(data) {
        self.upgradeState = .awaitingConnection(pendingBytes: [])
        self.removeDecoder(context: context)  // ← esto
    }
```

El nuestro:
```swift
case .beganConnecting:
    if case .end = unwrapInboundIn(data) {
        // No hacía nada — un comentario diciendo "esto no debería pasar"
    }
```

### Por qué importa

Cuando curl envía `CONNECT google.com:443`, el proxy recibe `.head` (el CONNECT) y luego `.end`. En paralelo, el proxy abre una conexión TCP a google.com. Hay una race condition: ¿qué llega primero, el `.end` del request HTTP o la confirmación de la conexión TCP?

En redes rápidas — localhost, LAN, cualquier servidor cercano — el `.end` llega primero. Siempre. Y nuestro código no hacía nada cuando eso pasaba. El `ByteToMessageHandler<HTTPRequestDecoder>` seguía en el pipeline, esperando más HTTP. Cuando los bytes TLS llegaban, el decoder los miraba, no entendía qué eran, y los descartaba. Sin error. Sin crash. Solo silencio.

Un `if` vacío. Eso era todo el bug.

### El segundo problema

Teníamos `host`, `port` e `intercept` almacenados dentro del enum de estado: `.awaitingEnd(host: String, port: Int, intercept: Bool)`. Pero `.beganConnecting` no tenía esos valores. Así que aunque supiéramos que faltaba la transición, no podíamos hacerla sin refactorizar.

Solución: sacar `host`, `port`, `intercept` del enum y guardarlos como propiedades de instancia. Simple. Debimos haberlo hecho desde el principio.

### El tercer detalle

Un `try?` silencioso al remover HTTPInterceptor del pipeline. Si fallaba (y podía fallar), el handler seguía ahí. Los bytes TLS entraban al HTTPInterceptor que intentaba parsearlos como HTTP. Más corrupción silenciosa.

### El momento

```bash
curl -s -o /dev/null -w "Status: %{http_code}" -x http://localhost:8080 https://www.google.com
Status: 200
```

Después de 4 implementaciones de GlueHandler, 6 pruebas fallidas, y una comparación línea por línea con el ejemplo de Apple — Google cargó a través de nuestro proxy. El túnel funcionaba.

```bash
curl -sk -x http://localhost:8080 https://httpbin.org/get
{"args":{},"headers":{"Accept":"*/*","Host":"httpbin.org"...}
```

Y la interceptación TLS también. El JSON de httpbin descifrado, pasando por nuestro CA cert, a través de un proxy que escribimos desde cero.

### Qué aprendimos

Las race conditions en SwiftNIO no crashean. No tiran errores. Los bytes simplemente desaparecen. La state machine necesita cubrir TODAS las combinaciones de orden de llegada, no solo las que "deberían pasar".

Y a veces el bug es un `if` vacío con un comentario que dice "esto no debería pasar". Siempre pasa.

**Fuentes que nos ayudaron:**
- [apple/swift-nio-examples/connect-proxy](https://github.com/apple/swift-nio-examples/tree/main/connect-proxy)
- [Swift Forums: HTTPRequestDecoder does not forward request](https://forums.swift.org/t/httprequestdecoder-does-not-forward-request/71484)
- [Swift Forums: Adding and removing handlers](https://forums.swift.org/t/adding-and-removing-handlers/54915)

---

## Sesión 2026-04-04

### El bug del body fantasma

Descubrimos que las responses HTTPS llegaban vacías al cliente. curl reportaba `error 18: transfer closed with 255 bytes remaining` — el proxy interceptaba, logueaba el body completo, pero el cliente recibía 0 bytes.

**Causa raíz**: SwiftNIO no flushea automáticamente. Escribíamos head y body con `write` (sin flush), y el `writeAndFlush` solo ocurría en `.end`. Pero httpbin.org cierra el TLS sin goodbye (`uncleanShutdown`), el `errorCaught` se disparaba antes del `.end`, y los bytes quedaban en el buffer.

**Primer intento fallido**: agregar `Connection: close` al response. No funcionó — URLSession en iOS lo ignora.

**Segundo intento fallido**: cerrar solo el canal remoto, no el del cliente. El proxy se saturaba porque el canal del cliente quedaba abierto indefinidamente.

**Fix final**: bufferear la response completa (head + body) y enviarla de un golpe con `writeAndFlush`, igual que mitmproxy. Funciona porque el flush es atómico — todos los bytes se envían antes de que NIO cierre el canal.

### El bug del "Waiting..."

La TUI mostraba "Waiting..." en responses HTTPS incluso cuando el cliente ya había recibido la respuesta. Causa: `TLSResponseForwarder` no tenía `requestId`, así que nunca llamaba `storeResponse()`. La TUI lee del `RequestStore`, no del canal NIO. Dos flujos de datos, ambos necesitan ser alimentados.

Fix: pasar `requestId` desde `handleDecryptedRequest()` a `TLSResponseForwarder` y llamar `storeResponse()` en `sendBufferedResponse()`.

### SimulationPry

Creamos una app iOS (SwiftUI) para testear Pry desde el Simulator. Botones para GET, POST, PUT, DELETE (HTTP y HTTPS), status codes (200, 404, 500), delays, headers, auth, y JSON bodies. El Simulator usa la red de la Mac — configurar proxy en WiFi settings intercepta el tráfico automáticamente.

Requisito descubierto: `Info.plist` necesita `NSAllowsArbitraryLoads = true` para requests HTTP (ATS lo bloquea por default).

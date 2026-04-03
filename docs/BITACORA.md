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

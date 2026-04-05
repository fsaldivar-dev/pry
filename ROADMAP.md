# Roadmap

## v0.1 — HTTP Proxy ✅
- [x] ProxyServer con SwiftNIO
- [x] HTTP forwarding
- [x] Mock responses por path
- [x] Logging a stdout + archivo
- [x] CLI: start, stop, mock, mocks, log, watch, help

## v0.2 — HTTPS/TLS ✅
- [x] CA certificate generation (P256, ECDSA)
- [x] Watchlist (.prywatch + CLI)
- [x] CONNECT handler state machine
- [x] `pry trust` — instalar CA en Simulator
- [x] HTTPS tunneling (GlueHandler + state machine fix)
- [x] TLS interception (MITM pipeline)
- [x] Detección de certificate pinning

## v0.3 — Testing & Quality ✅
- [x] Separar en PryLib + Pry (library + executable)
- [x] Unit tests (Watchlist, Config, RequestStore, CurlGenerator, AppIdentifier, ProxyError, BreakpointStore, WSFrame, ProjectScanner, CertPinning)
- [x] CI con `swift test` (macOS + Linux)
- [ ] Integration tests con proxy real

## v0.4 — Developer Experience ✅
- [x] TUI interactiva (3 paneles, keybindings, filtros, búsqueda)
- [x] Colores en stdout (Colors.swift, ANSI.swift)
- [x] Request/response body preview (BodyPrinter)
- [x] Copiar request como cURL (CurlGenerator)
- [x] Identificación de apps por User-Agent (AppIdentifier)
- [x] Modo headless (`--headless`)
- [x] `pry init` — genera .prywatch desde el proyecto

## v0.5 — Advanced Features ✅
- [x] WebSocket interception (RFC 6455 frame parsing)
- [x] Breakpoints (pausar y modificar requests)
- [x] Homebrew formula
- [x] Export HAR 1.2 (`pry export har`)
- [x] Header rewrite (`pry header add/remove`)
- [x] Map local (`pry map REGEX FILE`)
- [x] Map remote / redirects (`pry redirect SRC DST`)
- [x] Block list (`pry block DOMAIN` — responde 403)
- [x] DNS override (`pry dns DOMAIN IP`)
- [x] No-cache toggle (`pry nocache on/off`)
- [x] Request composer (`pry send METHOD URL`)
- [x] Session save/load (`pry save`/`pry load`)
- [x] Diff de requests (`pry diff ID1 ID2`)
- [x] Request repeat desde TUI (`r`)
- [x] Code generation: curl/swift/python (`g` en TUI)
- [x] TUI keybindings: diff (`d`), resume breakpoint (`b`)

## v0.6 — Scripting + Throttling ✅
- [x] DSL declarativo `.pryrules` (set-header, set-status, set-body, delay, drop)
- [x] GraphQL detector (deteccion automatica, icono 🔮 en TUI)
- [x] Network throttling (presets: 3g, slow, edge, wifi + custom)

## v0.7 — Estabilidad ✅
- [x] Buffered response en TLSResponseForwarder (fix uncleanShutdown, curl error 18)
- [x] Buffered response en ResponseForwarder (fix HTTP body delivery)
- [x] storeResponse en TLSResponseForwarder (fix TUI "Waiting...")
- [x] SimulationPry — app iOS para testing con Simulator

## No priorizadas

Estas features no fueron priorizadas. Si las necesitas, levanta un issue en GitHub:

- **SOCKS Proxy** — protocolo SOCKS5 (la mayoria de iOS devs usa HTTP proxy)
- **Protobuf Decoder** — decodificar Protocol Buffers a JSON (solo apps con protobuf)
- **gRPC Support** — interceptar trafico gRPC (requiere HTTP/2, muy nicho)

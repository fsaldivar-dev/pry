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
- [ ] Detección de certificate pinning

## v0.3 — Testing & Quality
- [ ] Separar en PryLib + Pry (library + executable)
- [ ] Unit tests para Watchlist, Config, MockHandler
- [ ] Integration tests con proxy real
- [ ] CI con swift test

## v0.4 — Developer Experience
- [ ] `pry init` — genera .prywatch desde el proyecto
- [ ] Colores en stdout (request verde, response azul, error rojo)
- [ ] Request/response body preview (truncado)
- [ ] Export log a HAR format

## Futuro
- [ ] WebSocket interception
- [ ] Breakpoints (pausar y modificar requests)
- [ ] Integración con AutoPilot
- [ ] Homebrew formula

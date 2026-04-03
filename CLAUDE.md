# Pry — Guia de Desarrollo

## Filosofia

- Swift puro + SwiftNIO, sin dependencias externas innecesarias
- Un solo binario CLI (`pry`) que controla todo
- Proxy HTTP/HTTPS selectivo — no rompe apps que no le pidas interceptar
- Documentacion en español, estilo libro tecnico

## Stack

- **CLI**: Swift 5.9+, macOS 13+, SPM
- **Networking**: SwiftNIO (Apple, MIT)
- **TLS**: SwiftNIO SSL + swift-certificates (Apple, MIT)
- **CI/CD**: GitHub Actions, macos-14 runner

## Estructura del proyecto

```
Sources/Pry/
├── main.swift              → Entry point, command dispatch
├── ProxyServer.swift       → ServerBootstrap, lifecycle
├── HTTPInterceptor.swift   → Captura HTTP requests, forwarding
├── ConnectHandler.swift    → CONNECT method, tunnel vs intercept
├── GlueHandler.swift       → Bidirectional byte forwarding (tunnel)
├── CertificateAuthority.swift → CA generation, cert cache
├── Watchlist.swift         → .prywatch domains management
├── MockHandler.swift       → Mock responses por path
├── Config.swift            → .pryconfig, logging, PID
├── ProxyError.swift        → Errores tipados
```

## Workflow de desarrollo

### 1. Planear
- Usar `/feature-dev` para features nuevas
- Para cambios pequenos, ir directo a implementar

### 2. Implementar
- Swift: sin dependencias externas innecesarias
- Seguir patrones existentes (command dispatch via switch, Config key=value)
- Errores tipados con ProxyError enum

### 3. Probar
- Compilar: `swift build`
- Probar HTTP: `pry start` + `curl -x http://localhost:8080 http://httpbin.org/get`
- Probar mocks: `pry mock /api/test '{"ok":true}'` + `curl -x http://localhost:8080 http://anything/api/test`
- Para CI: push a branch y verificar GitHub Actions

### 4. Revisar
- Correr `/simplify` para detectar codigo duplicado
- Correr `/code-review` antes de PR

### 5. Commitear
- Usar `/commit` para commits con mensaje consistente
- No commitear .build/, .pryconfig, .prywatch

### 6. PR
- Siempre crear PR para mergear a main
- PR debe incluir: summary, test plan
- Labels: major/minor/patch para release automatico

### 7. Documentar
- Usar `/docs` para documentar cambios como libro tecnico
- Actualizar README.md si hay features nuevos

## Convenciones de codigo

### Swift
- Command dispatch: switch en main.swift con guard para args
- Config: key=value en archivos planos (.pryconfig, .prywatch)
- Errors: ProxyError enum con CustomStringConvertible
- NIO Handlers: ChannelInboundHandler con state machines
- Logging: print a stdout + Config.appendLog para persistencia

### Comandos CLI
```bash
pry start [--port PORT]     # Levanta proxy
pry stop                    # Detiene proxy
pry add DOMAIN              # Agrega dominio a watchlist HTTPS
pry remove DOMAIN           # Quita dominio
pry list                    # Muestra dominios interceptados
pry mock PATH JSON          # Registra mock
pry mocks [clear]           # Lista/limpia mocks
pry log [clear]             # Muestra/limpia log
pry watch PATTERN           # Filtra trafico por dominio
pry trust                   # Instala CA en iOS Simulator
pry ca                      # Info del CA certificate
```

## Testing

### Manual
```bash
swift build
.build/debug/pry start
curl -x http://localhost:8080 http://httpbin.org/get
.build/debug/pry stop
```

### CI/CD
- Workflow `CI` — build + test en push/PR a main
- Workflow `Release` — version bump via PR labels, universal binary

## Limitaciones conocidas

- HTTPS tunneling WIP: GlueHandler bytes no fluyen despues de CONNECT 200
- TLS interception WIP: cert generation funciona, handshake no completa
- Solo macOS y Linux (Swift en Windows es experimental)

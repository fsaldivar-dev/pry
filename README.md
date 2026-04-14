<p align="center">
  <img src="assets/logo.png" alt="Pry" width="300">
</p>

<p align="center">
  <strong>Proxy HTTP/HTTPS para iOS devs. Swift puro. Un binario. Sin dependencias externas.</strong>
</p>

<p align="center">
  <a href="docs/libro/README.md">Leer el libro</a> •
  <a href="#inicio-rápido">Inicio rápido</a> •
  <a href="docs/libro/05-alternativas.md">Alternativas</a> •
  <a href="ROADMAP.md">Roadmap</a>
</p>

---

## Por qué existe

Existen herramientas excelentes para debuggear tráfico de red — Proxyman, Charles, mitmproxy. Cada una resuelve el problema a su manera y el trabajo que hay detrás merece respeto.

Lo que no existe es una alternativa open source en Swift, liviana, que se integre nativamente en el ecosistema iOS desde la terminal. Sin Python. Sin runtime. Sin UI. Un binario que intercepta, mockea y observa.

```bash
pry start
pry add api.myapp.com
pry mock /api/login '{"token":"abc123"}'
pry log
pry stop
```

## Qué descubrimos

Tres hallazgos que documentamos en el proceso:

**1. Los bytes no fluyen solos.** Después de responder `200 Connection Established` a un CONNECT, SwiftNIO no forwardea bytes automáticamente. Necesitas `leftOverBytesStrategy: .forwardBytes` en el HTTPRequestDecoder y remover handlers sincrónicamente con `syncOperations`. Sin esto, los bytes TLS se parsean como HTTP y crashean. → [Capítulo 3](docs/libro/03-connect-tunnel.md)

**2. El Simulador iOS usa la red de la Mac.** No hay network stack separado. Todo request HTTP/HTTPS del Simulador sale por la interfaz de red de macOS. Configurar un proxy en el sistema intercepta tráfico del Simulador automáticamente. → [Capítulo 1](docs/libro/01-el-problema.md)

**3. HTTPS selectivo es posible.** No necesitas interceptar todo el tráfico TLS. Solo los dominios que el dev pida (`.prywatch`). El resto pasa como túnel transparente — las apps que no te interesan no se rompen. → [Capítulo 4](docs/libro/04-tls-interception.md)

## El libro

Documentamos todo el proceso — los errores, los callejones sin salida, las decisiones. No para vender Pry, para que cualquier ingeniero que quiera construir un proxy tenga un punto de partida.

| Capítulo | Qué encontrarás |
|---|---|
| [01 — El problema](docs/libro/01-el-problema.md) | Qué existe, qué falta, y por qué decidimos construirlo |
| [02 — Arquitectura](docs/libro/02-arquitectura.md) | SwiftNIO pipelines, channel handlers, event loops |
| [03 — CONNECT y el túnel](docs/libro/03-connect-tunnel.md) | GlueHandler, por qué los bytes no fluyen, state machines |
| [04 — TLS interception](docs/libro/04-tls-interception.md) | CA generation, SNI extraction, pipeline MITM |
| [05 — Alternativas](docs/libro/05-alternativas.md) | mitmproxy, Proxyman, Charles — análisis honesto |
| [06 — Decisiones](docs/libro/06-decisiones.md) | Por qué Swift, por qué SwiftNIO, por qué no wrappear mitmproxy |
| [07 — Por qué es libre](docs/libro/07-por-que-es-libre.md) | La deuda con el open source y por qué documentamos los fracasos |

> **[Leer el libro completo →](docs/libro/README.md)**

---

<h2 id="inicio-rápido">Inicio rápido</h2>

### Homebrew (recomendado)

```bash
brew tap fsaldivar-dev/pry
brew install pry
```

### Desde fuente

```bash
swift build -c release
cp .build/release/pry /usr/local/bin/pry

# Levantar proxy
pry start

# En otra terminal: probar
curl -x http://localhost:8080 http://httpbin.org/get
```

### Mockear endpoints

```bash
pry mock /api/login '{"token":"abc123"}'
pry mock /api/users users.json
curl -x http://localhost:8080 http://anything/api/login
# → {"token":"abc123"}
```

### HTTPS selectivo

```bash
# Agregar dominios a interceptar
pry add api.myapp.com
pry add staging.myapp.com

# Instalar CA en el Simulador iOS
pry trust

# Levantar — intercepta solo lo de la watchlist
pry start
```

### Ver tráfico

```bash
pry log          # Historial de requests
pry list         # Dominios interceptados
pry mocks        # Mocks activos
```

### TUI interactiva

Al ejecutar `pry start`, se abre una interfaz interactiva en terminal con 3 paneles: lista de requests, detalle, y response body.

```bash
pry start              # TUI interactiva (default)
pry start --headless   # Sin TUI, solo logging a stdout
pry start --port 9090  # Puerto custom
```

**Indicadores:**

| Icono | Significado |
|-------|-------------|
| 🟢 | Respuesta exitosa (2xx) |
| 🔴 | Error (4xx/5xx) |
| 🟡 | Respuesta mockeada |
| 🔒 | Túnel HTTPS (no interceptado) |
| ⏳ | Esperando respuesta |

### Filtrar tráfico

```bash
pry watch api.myapp.com   # Solo mostrar tráfico de este dominio
pry watch clear           # Limpiar filtro
```

### Comandos avanzados

#### No-cache

```bash
pry nocache on            # Agrega Cache-Control: no-store a todos los requests
pry nocache off           # Desactiva no-cache
```

#### Bloquear dominios

```bash
pry block ads.tracker.com     # Bloquea dominio (responde 403)
pry blocks                    # Lista dominios bloqueados
pry blocks clear              # Limpia lista de bloqueo
```

#### Redirigir hosts

```bash
pry redirect api.prod.com api.staging.com   # Redirige todo el tráfico
pry redirects                               # Lista redirects activos
pry redirects clear                         # Limpia redirects
```

#### DNS override

```bash
pry dns api.myapp.com 127.0.0.1   # Resuelve dominio a IP custom
pry dns list                       # Lista overrides activos
pry dns clear                      # Limpia overrides
```

#### Componer requests

```bash
pry send GET https://api.myapp.com/users
pry send POST https://api.myapp.com/login --header "Content-Type: application/json" --body '{"user":"admin"}'
```

#### Sesiones

```bash
pry save session.pry      # Guarda requests capturados a archivo
pry load session.pry      # Carga sesion guardada
```

#### Comparar requests

```bash
pry diff 1 3              # Compara request #1 con #3 (headers, body, status)
```

#### HAR export

```bash
pry export har traffic.har    # Exporta tráfico capturado como HAR 1.2
```

#### Header rewrite

```bash
pry header add Authorization "Bearer token123"    # Agrega header a todos los requests
pry header remove Cookie                          # Elimina header de todos los requests
pry headers                                       # Lista reglas activas
pry headers clear                                 # Limpia reglas
```

#### Map local

```bash
pry map '/api/v1/.*' mock-data.json    # Responde con archivo local para URLs que matcheen
pry maps                               # Lista maps activos
pry maps clear                         # Limpia maps
```

#### Breakpoints

```bash
pry break /api/login      # Pausa requests que matcheen el patrón
pry breaks                # Lista breakpoints activos
pry breaks clear          # Limpia breakpoints
```

#### Escanear proyecto

```bash
pry init                  # Escanea directorio actual buscando dominios API
pry init ./MyApp          # Escanea directorio específico
```

### Scripting (.pryrules)

Crea un archivo de reglas declarativas para modificar requests y responses:

```
rule "/api/*"
  set-header Authorization "Bearer token123"
  remove-header Cookie

rule "POST /api/auth"
  set-status 200
  set-body '{"token":"mock"}'

rule "*.tracker.com"
  drop

rule "/api/slow"
  delay 2000
```

```bash
pry rules load rules.pry   # Cargar archivo de reglas
pry rules                   # Ver reglas activas
pry rules clear             # Limpiar reglas
```

Acciones: `set-header`, `remove-header`, `replace-host`, `replace-port`, `replace-path`, `set-status`, `set-body`, `delay`, `drop`

### Network Throttling

```bash
pry throttle 3g             # 750 KB/s, 200ms latencia
pry throttle slow           # 100 KB/s, 500ms
pry throttle edge           # 50 KB/s, 800ms
pry throttle wifi           # 5 MB/s, 10ms
pry throttle --bandwidth 256 --latency 100   # Custom
pry throttle off            # Desactivar
```

### GraphQL

Pry detecta automáticamente queries GraphQL en requests POST. En la TUI aparecen con el icono 🔮 y el nombre de la operación.

### Modo headless

Para CI/CD, scripts, o logging sin TUI:

```bash
pry start --headless &
curl -x http://localhost:8080 http://api.com/test
pry export har results.har
pry stop
```

### Comandos inline (TUI)

Mientras el proxy corre en la TUI, puedes escribir comandos directamente sin reiniciar:

```
mock /api/test '{"ok":true}'
add api.myapp.com
header add X-Debug "true"
export har traffic.har
```

### Code generation (TUI)

Dentro de la TUI, la tecla `g` cicla entre formatos de generacion de codigo: **curl**, **swift** y **python**. La tecla `c` copia el request seleccionado en el formato activo al clipboard.

```
g → cicla: curl → swift → python
c → copia al clipboard en el formato seleccionado
```

### TUI interactiva (keybindings completos)

**Keybindings:**

| Tecla | Accion |
|-------|--------|
| `↑` `↓` | Navegar requests |
| `c` | Copiar request en formato seleccionado (curl/swift/python) |
| `f` | Ciclar filtros (GET, POST, PUT, DELETE, 2xx, 4xx, 5xx) |
| `/` | Buscar por URL, host, metodo o body |
| `g` | Ciclar formato de code generation (curl/swift/python) |
| `d` | Diff del request seleccionado con el anterior |
| `b` | Reanudar request pausado por breakpoint |
| `r` | Repetir request seleccionado |
| `Tab` | Alternar entre requests y mocks activos |
| `Esc` | Limpiar filtro/busqueda |
| `q` | Salir |

### App de testing (iOS Simulator)

SimulationPry es una app iOS incluida para probar Pry con el Simulator:

```bash
# 1. Configura Pry
pry add httpbin.org
pry trust
pry start

# 2. Abre SimulationPry/SimulationPry.xcodeproj en Xcode
# 3. Corre en el Simulator
# 4. Presiona los botones — cada request aparece en la TUI
```

La app tiene botones para GET, POST, PUT, DELETE (HTTP y HTTPS), status codes, delays, headers con auth, y JSON bodies.

---

## Alternativas

Si tu caso de uso es diferente, estas herramientas pueden ser mejor opción:

| Caso | Herramienta | Por qué |
|---|---|---|
| UI visual completa | [Proxyman](https://proxyman.io) | macOS nativo, SSL proxying, breakpoints |
| Multiplataforma, enterprise | [Charles Proxy](https://www.charlesproxy.com) | Estándar de industria, Java |
| Open source, Python | [mitmproxy](https://mitmproxy.org) | Potente, extensible, UI web |
| Inspección sin proxy | [HTTP Toolkit](https://httptoolkit.com) | Open source, UI multiplataforma |

Análisis completo: [Capítulo 5 — Alternativas](docs/libro/05-alternativas.md)

---

## Bitácora

Diario crudo de desarrollo — cada sesión, cada intento, cada error.

> **[Leer la bitácora →](docs/BITACORA.md)**

---

## Aviso legal

Pry es una herramienta de desarrollo para depurar trafico de red en tus propias aplicaciones y ambientes autorizados. La intercepcion de trafico de red ajeno sin consentimiento es ilegal en la mayoria de jurisdicciones. Usa esta herramienta de forma responsable.

## Licencia

MIT — ver [LICENSE](./LICENSE)

Las dependencias de Apple (SwiftNIO, swift-certificates, swift-crypto) estan licenciadas bajo Apache 2.0. Ver [NOTICE](./NOTICE) para detalles.

---

> *El conocimiento se pudre cuando se guarda. Se mantiene vivo cuando se comparte.* — [Manifiesto](./MANIFESTO.md)

# Pry — Ingeniería de un proxy HTTP/HTTPS desde cero

> *El conocimiento se pudre cuando se guarda. Se mantiene vivo cuando se comparte.*

---

Este no es un manual de usuario. Es la documentación técnica de cómo se construye un proxy HTTP/HTTPS con SwiftNIO, desde cero, sin depender de mitmproxy ni de ningún runtime externo.

Pry nació de una pregunta simple: ¿se puede construir un proxy HTTP/HTTPS en Swift puro, sin depender de Python ni de runtimes externos, que se integre nativamente en el ecosistema iOS? La respuesta involucró SwiftNIO channel pipelines, state machines para CONNECT tunneling, generación de certificados X.509 on-the-fly, y el descubrimiento de que hacer que los bytes fluyan bidireccialmente es más difícil de lo que parece.

Documentamos todo — los errores, los intentos fallidos, las decisiones — para que cualquier ingeniero que quiera construir un proxy tenga un punto de partida.

---

## Contenido

### El libro

1. **[El problema](01-el-problema.md)** — Qué existe hoy, qué falta, y por qué decidimos construirlo
2. **[Arquitectura](02-arquitectura.md)** — SwiftNIO pipelines, channel handlers, event loops, y cómo fluye un request a través del proxy
3. **[CONNECT y el túnel](03-connect-tunnel.md)** — El método CONNECT, GlueHandler, por qué los bytes no fluyen, y cómo Apple resolvió esto
4. **[TLS interception](04-tls-interception.md)** — Generación de CA, certificados on-the-fly, SNI extraction, y el pipeline MITM
5. **[Alternativas](05-alternativas.md)** — mitmproxy, Proxyman, Charles, HTTP Toolkit — qué hacen bien y por qué elegimos otro camino
6. **[Decisiones](06-decisiones.md)** — ADRs: por qué Swift, por qué SwiftNIO, por qué no wrappear mitmproxy
7. **[Por qué es libre](07-por-que-es-libre.md)** — La deuda con el open source y por qué documentamos los fracasos
8. **[La TUI](08-tui.md)** — Raw mode, ANSI escape sequences, tres paneles, dirty flags
9. **[Features que nadie pidió](09-features-avanzadas.md)** — Mocks, breakpoints, export, el pipeline completo de interception
10. **[Scripting sin scripting](10-scripting.md)** — DSL declarativo, throttling, GraphQL auto-detection
11. **[La comparativa honesta](11-comparativa.md)** — Pry vs Proxyman vs mitmproxy — qué logramos y qué no

### Apéndices

- **[Referencia de comandos](../apendices/comandos.md)** — Los comandos del CLI
- **[Troubleshooting](../apendices/troubleshooting.md)** — Errores comunes y cómo resolverlos

### Referencia

- **[Bitácora](../BITACORA.md)** — Diario de laboratorio crudo (cada sesión, cada intento)
- **[Roadmap](../../ROADMAP.md)** — Fases futuras

---

## Cómo leer este libro

Si quieres entender **por qué existe** Pry, lee el [Capítulo 1](01-el-problema.md).

Si quieres entender **cómo funciona** por dentro, lee el [Capítulo 2](02-arquitectura.md).

Si quieres ver **ingeniería real** — intentos fallidos, bytes que no fluyen, pipelines que crashean — lee los Capítulos [3](03-connect-tunnel.md) y [4](04-tls-interception.md).

Si quieres **usar** Pry, ve al [README principal](../../README.md).

---

*Todo el contenido está en español. El código fuente y los ejemplos usan convenciones en inglés donde es idiomático.*

# Capítulo 5 — Alternativas

## Por qué hablar de la competencia

El espacio de proxies HTTP para desarrollo iOS tiene herramientas maduras, bien financiadas, con comunidades activas. Algunas tienen años de ventaja, ecosistemas de plugins, soporte comercial. Son buenas herramientas. Merecen reconocimiento honesto.

Lo que ofrecemos aquí es un análisis técnico sin trucos: qué hace bien cada herramienta, dónde Pry toma un camino diferente. Con esa información, puedes elegir.

---

## mitmproxy

**Repositorio:** [mitmproxy/mitmproxy](https://github.com/mitmproxy/mitmproxy) — 38K+ stars
**Lenguaje:** Python | **Licencia:** MIT | **Precio:** Gratuito

mitmproxy no es una herramienta — es un ecosistema. Incluye tres interfaces: `mitmproxy` (TUI), `mitmdump` (CLI), y `mitmweb` (interfaz web). Su poder real está en los addons: scripts Python que se ejecutan para cada request.

**Lo que hace mejor que Pry:** El sistema de addons es incomparable. Si necesitas lógica compleja de intercepción — transformar requests, agregar headers dinámicamente, modificar respuestas — mitmproxy lo soporta sin fricción.

**La fricción:** Requiere Python. En un equipo iOS, eso significa una runtime extra, un entorno virtual, pip, posiblemente conflictos de versiones.

---

## Proxyman

**Sitio:** [proxyman.io](https://proxyman.io)
**Lenguaje:** Swift / macOS native | **Licencia:** Comercial | **Precio:** $99/año

Proxyman es lo que pasa cuando alguien construye una herramienta nativa de macOS con amor. La UI es excelente. La integración con el Simulador iOS es inmediata. La feature de "Breakpoints" permite pausar un request en vuelo y modificarlo manualmente.

**Lo que hace mejor que Pry:** La experiencia completa de UI es un nivel diferente. Si pasas horas debuggeando tráfico de red, la inversión se recupera en días.

**La fricción:** macOS-only y de pago. En entornos de CI, la CLI existe pero no es la prioridad del producto.

---

## Charles Proxy

**Sitio:** [charlesproxy.com](https://www.charlesproxy.com)
**Lenguaje:** Java | **Licencia:** Comercial | **Precio:** $50 licencia perpetua

El veterano. Desde 2002, generaciones de developers han usado Charles para debuggear tráfico. "Map Remote", "Map Local", "Rewrite" — un conjunto de herramientas construido sobre años de feedback real.

**Lo que hace mejor que Pry:** La madurez. Hay edge cases que Charles maneja porque alguien los reportó hace diez años.

**La fricción:** Corre en la JVM. El look and feel no es nativo de macOS.

---

## HTTP Toolkit

**Repositorio:** [httptoolkit/httptoolkit](https://github.com/httptoolkit/httptoolkit)
**Lenguaje:** TypeScript / Electron | **Licencia:** AGPL / Comercial | **Precio:** Gratuito / $14/mes Pro

Interceptación automática por plataforma. Modifica las variables de entorno del proceso para activar el proxy automáticamente. Multi-plataforma de verdad: macOS, Linux, Windows.

**Lo que hace mejor que Pry:** La historia multi-plataforma es real. Si tu equipo trabaja en Linux, Windows y macOS, HTTP Toolkit tiene presencia en todos lados.

**La fricción:** Electron. Para iOS, la integración con el Simulador requiere configuración manual.

---

## Tabla comparativa

| | mitmproxy | Proxyman | Charles | HTTP Toolkit | **Pry** |
|---|---|---|---|---|---|
| **Lenguaje** | Python | Swift | Java | TypeScript | Swift |
| **Licencia** | MIT | Comercial | Comercial | AGPL / Comercial | MIT |
| **Precio** | Gratuito | $99/año | $50 | $14/mes | Gratuito |
| **HTTPS** | Total | Total | Total | Total | Selectivo |
| **CLI** | Excelente | Limitado | Limitado | Moderado | Central |
| **Dependencias** | Python + pip | Ninguna | JVM | Node + npm | Ninguna |
| **Código fuente** | Abierto | Cerrado | Cerrado | Parcial | Abierto |

---

## Lo que Pry ofrece diferente

**Swift nativo, cero dependencias.** Un binario que compilas con `swift build`. Sin Python, sin JVM, sin Node. Para un developer iOS, una herramienta que habla el mismo idioma que su stack.

**HTTPS selectivo.** Las demás interceptan todo o nada. Pry intercepta solo los dominios que pides. El resto pasa como túnel transparente. Tus apps que no te interesan siguen funcionando.

**CLI-first.** Diseñado para integrarse en scripts, en CI, en flujos de testing automatizado.

**Código legible.** Menos de 2,000 líneas de Swift. Puedes leerlo todo en una tarde.

---

## Cuándo no usar Pry

Si pasas horas inspeccionando tráfico con una UI, usa Proxyman o Charles.

Si necesitas addons de Python para transformar tráfico, usa mitmproxy.

Si tu equipo necesita herramientas en Windows y Linux, HTTP Toolkit o mitmproxy tienen más sentido.

Pry tiene sentido cuando quieres una herramienta que puedas leer, modificar y confiar. Cuando CLI no es una limitación sino una ventaja.

---

## Qué aprendimos

Construir Pry no fue construirlo a pesar de que existen herramientas excelentes. Fue construirlo porque el espacio que ocupa — Swift nativo, selectivo, CLI-first — no estaba ocupado.

Las herramientas que describimos aquí merecen el respeto que se gana con años de trabajo real. No estamos aquí para reemplazarlas. Estamos aquí para ofrecer una alternativa diferente.

---

**Siguiente: [Capítulo 6 — Decisiones](06-decisiones.md)**

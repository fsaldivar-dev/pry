# Capítulo 6 — Decisiones

## El formato ADR

Cada decisión técnica tiene un costo. No hay arquitecturas perfectas — hay compromisos que se hacen conscientemente o inconscientemente. La diferencia entre una codebase que envejece bien y una que se convierte en deuda es si las decisiones se documentaron o se olvidaron.

---

## ADR-001: Por qué Swift

### Contexto

Un proxy HTTP puede escribirse en cualquier lenguaje. Pry vive en el ecosistema iOS. Los developers que lo usan escriben Swift. Las herramientas de las que depende — SwiftNIO, swift-certificates — son Swift.

### Opciones

- **Python:** Llegar rápido. Ecosistema maduro. Costo: runtime externo fuera del ecosistema iOS.
- **Go:** Binarios sin dependencias. Costo: lenguaje extraño para developers iOS.
- **Rust:** Velocidad, seguridad de memoria. Costo: barrera de entrada significativa.
- **Swift:** Lenguaje nativo de la plataforma. Costo: ecosistema más limitado fuera de Apple.

### Decisión

Swift.

### Consecuencias

**Lo que ganamos:** Cero fricción de toolchain. SwiftNIO como opción natural. Código legible para developers iOS.

**Lo que perdemos:** Distribución en Linux con fricción. Ecosistema de librerías de networking más pequeño. Contribuciones de la comunidad amplia requieren aprender Swift.

---

## ADR-002: Por qué SwiftNIO

### Contexto

Para un servidor TCP que maneje múltiples conexiones en Swift, hay varias opciones.

### Opciones

- **Network.framework:** Moderno, API nativa. Diseñado para clientes, no servidores.
- **URLSession:** Estándar para HTTP. No expone el control sobre TCP que un proxy necesita.
- **SwiftNIO:** Framework async de Apple para servidores. Channel pipelines, handlers modulares.
- **POSIX sockets directos:** Control total. Cero dependencias. Implementar todo manualmente.

### Decisión

SwiftNIO.

### Consecuencias

**Lo que ganamos:** Modelo claro de pipeline. Backpressure y concurrencia resueltos. Integración natural con SwiftNIO SSL.

**Lo que perdemos:** Curva de aprendizaje significativa. Debugging difícil — cuando falla, los bytes desaparecen en silencio. El Capítulo 3 documenta eso en detalle.

---

## ADR-003: Por qué no envolver mitmproxy

### Contexto

La pregunta obvia: ¿por qué no hacer `shell out` a mitmproxy? mitmproxy tiene más de una década de desarrollo y maneja edge cases que tardaríamos años en descubrir.

### Opciones

- **Wrapper sobre mitmproxy:** Pry como CLI Swift que lanza mitmproxy como proceso hijo.
- **Implementación propia:** Escribir el proxy desde cero con SwiftNIO.

### Decisión

Implementación propia.

### Consecuencias

**Lo que ganamos:** La dependencia de Python desaparece. Control total sobre la intercepción selectiva. Código legible y modificable. Cero overhead de IPC.

**Lo que perdemos:** Años de desarrollo que mitmproxy ya tiene. El sistema de addons. Velocidad de desarrollo inicial. Edge cases que descubriremos uno a uno.

Esta decisión tiene un costo real. No fingimos que sea gratuita. Pero la alternativa era una herramienta que necesita Python — y eso contradice el objetivo central.

---

## ADR-004: Por qué HTTPS selectivo

### Contexto

La solución estándar es interceptar todo HTTPS. Eso tiene un costo: las apps con certificate pinning fallan. La fricción está en la dirección equivocada: el default es interceptar todo, y el usuario tiene que excluir lo que no quiere.

### Opciones

- **Interceptar todo (opt-out):** El modelo estándar. El usuario excluye dominios.
- **No interceptar HTTPS:** Simple. Limitado — en 2026 casi todo es HTTPS.
- **Interceptar selectivamente (opt-in):** Túnel transparente por defecto. Solo los dominios en la watchlist reciben MITM.

### Decisión

Interceptar selectivamente. Túnel transparente como default.

### Consecuencias

**Lo que ganamos:** Las apps fuera de la watchlist funcionan normal. Modelo mental más seguro. Menos superficie de ataque.

**Lo que perdemos:** Menos conveniencia para quien quiere ver todo. El ConnectHandler necesita decidir en tiempo de conexión — más complejidad en la state machine.

---

## ADR-005: Por qué CLI-first

### Contexto

Las herramientas de debugging más exitosas tienen UI. Construir una UI tiene beneficios obvios: más accesible, más visible.

### Opciones

- **UI-first:** Aplicación macOS nativa o interfaz web.
- **CLI-first:** CLI como interfaz primaria, sin excluir UI futura.

### Decisión

CLI-first.

### Consecuencias

**Lo que ganamos:** Automatización como ciudadana de primera clase. Funciona en CI, SSH, entornos sin display. Config como archivos de texto versionables en git.

**Lo que perdemos:** Accesibilidad para usuarios que no viven en la terminal. Visualización en tiempo real más difícil. El onboarding requiere leer documentación.

Pry no es para todos — es para el developer que ya vive en la terminal y prefiere configuración como código.

---

## Qué aprendimos

El código dice qué hace el sistema. Los ADRs dicen por qué. Cuando alguien en el futuro quiera agregar una UI a Pry, el ADR-005 explica por qué no la hay — no como prohibición sino como contexto. La decisión puede cambiar. Lo importante es que el cambio sea consciente.

---

**Siguiente: [Capítulo 7 — Por qué es libre](07-por-que-es-libre.md)**

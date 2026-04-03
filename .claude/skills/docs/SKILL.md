---
name: docs
description: Documentar cambios como libro técnico — investigación primero, código como subproducto
---

# /docs — Documentación como libro técnico

## Visión

El conocimiento se pudre cuando se guarda. Se mantiene vivo cuando se comparte.

La documentación de Pry no es un manual de usuario. Es un libro técnico que documenta el proceso de construir un proxy HTTP/HTTPS desde cero con SwiftNIO. Los errores y los callejones sin salida son tan valiosos como los éxitos.

## Principios

- Documenta el viaje, no solo el destino
- Los errores y descubrimientos son tan valiosos como los éxitos
- Filosofía antes que features, problema antes que solución
- Lista alternativas honestamente (mitmproxy, Proxyman, Charles)
- El código es un subproducto de la investigación
- Tono: investigador/profesor, nunca vendedor
- Siempre en español

## Estructura del libro

```
docs/
├── README.md               (índice del libro)
├── 01-el-problema.md       (por qué Proxyman cuesta $89 y mitmproxy tiene 50K líneas)
├── 02-arquitectura.md      (SwiftNIO pipelines, channel handlers, event loops)
├── 03-connect-tunnel.md    (CONNECT method, GlueHandler, por qué los bytes no fluyen)
├── 04-tls-interception.md  (CA generation, SNI extraction, MITM pipeline)
├── 05-alternativas.md      (mitmproxy, Proxyman, Charles, HTTP Toolkit — análisis honesto)
├── 06-decisiones.md        (ADRs: por qué Swift, por qué SwiftNIO, por qué no mitmproxy)
└── apendices/
    ├── comandos.md         (referencia CLI)
    └── troubleshooting.md  (errores comunes)
```

## Reglas del README

- Máximo ~150 líneas efectivas
- Estructura: Logo → Por qué existe → Quick start → Stack → Licencia → Manifiesto
- NO documentación técnica profunda (eso va en el libro)
- SÍ debe provocar curiosidad

## Reglas de capítulos

- Autocontenidos (legibles sin capítulos anteriores)
- Problema primero
- Diagramas Mermaid donde ayuden
- Documenta errores/fracasos, no solo éxitos
- Termina con "Qué aprendimos" + enlaces relacionados
- Tono narrativo (explicando a un colega senior en un café)

## Reglas inquebrantables

- NUNCA poner docs técnicos profundos en README
- NUNCA usar lenguaje de marketing
- NUNCA duplicar contenido (usar enlaces)
- SIEMPRE documentar errores y éxitos
- SIEMPRE explicar "por qué" antes de "cómo"
- SIEMPRE listar alternativas
- SIEMPRE escribir en español
- SIEMPRE usar diagramas Mermaid donde sea más claro

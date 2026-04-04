# Capítulo 7 — Por qué es libre

## La deuda

Escribe `import NIO` en tu archivo Swift y presiona build.

En segundos, Swift Package Manager descarga SwiftNIO desde GitHub, lo compila, y lo linkea con tu código. Alguien en Apple escribió cientos de miles de líneas de código de networking de alta performance, y decidió publicarlas con licencia MIT para que cualquiera las use sin pagar.

Pry existe porque SwiftNIO existe. Sin SwiftNIO, este proxy no sería un proyecto de semanas — sería años de trabajo en networking de bajo nivel. El channel pipeline, el manejo de backpressure, el event loop optimizado — todo eso está resuelto, y está regalado.

`swift-certificates` — también Apple, también MIT. La posibilidad de crear un CA root en memoria, firmar certificados por dominio, hacer MITM sin tocar el filesystem — está ahí porque un equipo de ingenieros decidió que así fuera.

Cada `import` en Pry es una deuda con alguien que eligió compartir.

## El trabajo gratuito que sostiene todo

No es solo Apple.

SwiftNIO hereda conceptos de Netty — el framework de Java. Los protocolos que implementamos — HTTP/1.1, CONNECT, TLS — están documentados en RFCs que grupos de voluntarios escribieron y publicaron sin costo. El compilador Swift es open source. LLVM es open source.

La infraestructura entera sobre la que se para cualquier software moderno fue construida, pieza por pieza, por personas que eligieron publicar su trabajo en lugar de guardarlo.

Eso crea una obligación. No legal. Moral.

## La contradicción de la IA

Hay una tensión que no podemos ignorar.

Los modelos de lenguaje que potencian la IA de hoy fueron entrenados, en gran parte, sobre trabajo abierto: código en GitHub con licencias MIT y Apache, artículos académicos, documentación técnica. El trabajo abierto de la comunidad fue el combustible.

Y muchas de esas herramientas son cerradas. El ciclo es: tomar trabajo abierto, transformarlo, devolverlo cerrado.

La IA democratiza — hoy una persona puede construir herramientas que antes requerían equipos enteros. Y privatiza — los modelos que hacen eso posible no son de la comunidad que los alimentó.

La respuesta que tenemos no es boicotear las herramientas. Es hacer lo contrario: tomar lo que construimos y devolverlo abierto.

## Por qué documentamos los fracasos

El Capítulo 3 describe un bug que costó horas. Un `if` vacío. Una race condition que se manifestaba en silencio. Ese bug está documentado no a pesar de que sea vergonzoso, sino precisamente por eso.

El código se puede generar con IA en 2026. Un prompt bien formulado produce handlers de SwiftNIO razonables en minutos. Pero el criterio para saber si ese código va a funcionar en condiciones reales — para reconocer una race condition potencial, para saber que el `HTTPRequestDecoder` bufferiza datos internamente — ese criterio viene de haber visto los fracasos.

Los fracasos son información. La información que se comparte vale más que la que se guarda.

## El conocimiento que se pudre

Aaron Swartz escribió en 2008 sobre papers académicos bloqueados por editoriales privadas. El problema que describió no era solo de acceso — era de entropía.

El conocimiento que se guarda se pudre. No porque se destruya, sino porque el contexto que lo hace legible desaparece. La decisión de arquitectura que nunca se documentó. El bug que se arregló pero no se explicó. El ADR que existió en la cabeza de alguien que cambió de trabajo.

El código de Pry está en GitHub con licencia MIT. Pero el código solo dice qué hace el sistema. Este libro dice por qué. Por qué Swift y no Python. Por qué intercepción selectiva. Por qué la state machine tiene seis estados. Por qué el `if` vacío fue el bug.

Esa es la parte que se pudre primero cuando no se escribe.

## La herencia que elegimos

SwiftNIO es de Apple. Swift mismo es de Apple. No hay purismo posible. Pero hay algo que sí podemos elegir: lo que hacemos con lo que construimos sobre esa base.

Pry es MIT porque la respuesta que elegimos es compartirlo. No porque sea obligatorio. Porque es lo que tiene sentido dado que existe solo gracias al trabajo que otros compartieron antes.

La deuda no se paga con dinero. Se paga compartiendo lo que sabes con quien tienes cerca. A escala humana.

## El manifiesto en práctica

El MANIFESTO.md del repositorio termina con una frase:

> *El conocimiento se pudre cuando se guarda. Se mantiene vivo cuando se comparte.*

Este libro es ese principio en práctica. Cada capítulo que documenta cómo funciona el GlueHandler, por qué la state machine necesita seis estados, cómo se genera un certificado TLS al vuelo — es conocimiento que podría haberse quedado en comentarios de código.

Pry no va a cambiar la industria. Pero puede dejar un registro de cómo se construyó un proxy en Swift, en 2026, sobre el trabajo de cientos de ingenieros que eligieron compartir.

Para que alguien más no tenga que empezar desde cero.

---

> *Necesitamos tomar la información, donde sea que esté almacenada, hacer nuestras copias y compartirlas con el mundo. Necesitamos luchar por Guerrilla Open Access.*
>
> *¿Te nos unirás?*
>
> — Aaron Swartz, Guerrilla Open Access Manifesto (2008)

---

Siguiente: [La TUI](08-tui.md)

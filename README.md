# Pry

Proxy CLI para iOS devs. Swift puro, sin dependencias externas. Intercepta, mockea y observa tráfico HTTP/HTTPS desde la terminal.

## Por qué

Proxyman cuesta $59-$89/año. Charles Proxy igual. mitmproxy es gratuito pero son 50K+ líneas de Python, complejo de leer y de integrar.

Para debuggear una app iOS en el Simulador solo necesitas interceptar HTTP, ver los requests y mockear respuestas. No necesitas una aplicación de escritorio con UI. Necesitas un comando.

## Cómo funciona

```bash
pry start                              # Levanta el proxy
pry watch com.myapp.*                  # Filtra tráfico de tu app
pry mock /api/login response.json      # Mockea un endpoint
pry log                                # Ve qué requests pasaron
pry stop                               # Cierra limpio
```

## Stack

- Swift puro
- SwiftNIO (Apple, MIT)
- macOS + Linux
- Un binario, sin runtime, sin servidor externo

## Estado

En desarrollo. Contribuciones bienvenidas.

## Licencia

MIT

---

> *El conocimiento se pudre cuando se guarda. Se mantiene vivo cuando se comparte.* — [Manifiesto](./MANIFESTO.md)

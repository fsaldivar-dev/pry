<p align="center">
  <img src="assets/logo.png" alt="Pry" width="300">
</p>

# Pry

Proxy CLI para iOS devs. Swift puro, sin dependencias externas. Intercepta, mockea y observa tráfico HTTP/HTTPS desde la terminal.

## Por qué

Existen herramientas excelentes para debuggear tráfico de red — Proxyman, Charles, mitmproxy. Cada una resuelve el problema a su manera y el trabajo que hay detrás merece respeto.

Lo que no existe es una alternativa open source en Swift, liviana, sin dependencias externas, pensada para integrarse nativamente en el ecosistema iOS desde la terminal.

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

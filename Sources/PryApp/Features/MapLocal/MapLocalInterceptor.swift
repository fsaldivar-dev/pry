import Foundation
import PryLib

/// Interceptor de phase `.resolve` que responde con el contenido de un archivo
/// local cuando la URL matchea algún pattern en `MapLocalStore`. Corre después
/// del `.gate` (Blocking) — si no lo bloquearon, quizá lo mapee a un archivo.
///
/// El Content-Type se infiere de la extensión del archivo (ver `contentType(for:)`).
/// Si el archivo no existe o no se puede leer, responde con `.notFound()` para
/// señalizar que el mapping está roto sin ir al servidor real.
@available(macOS 14, *)
public struct MapLocalInterceptor: Interceptor {
    public let phase: Phase = .resolve
    private let store: MapLocalStore

    public init(store: MapLocalStore) {
        self.store = store
    }

    public func intercept(_ ctx: RequestContext) async -> InterceptResult {
        let fullURL = ctx.host + ctx.path
        let matched = await MainActor.run { store.match(url: fullURL) }
        guard let filePath = matched else { return .pass }

        let resolved = (filePath as NSString).standardizingPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: resolved)) else {
            return .shortCircuit(.notFound())
        }

        return .shortCircuit(Response(
            status: 200,
            headers: ["Content-Type": contentType(for: resolved)],
            body: data
        ))
    }
}

/// Infiere el Content-Type a partir de la extensión del archivo. Cubre los tipos
/// más comunes en dev (JSON, JS, HTML, CSS, imágenes). Default `application/octet-stream`
/// para extensiones desconocidas — el cliente debe saber qué esperar.
@available(macOS 14, *)
func contentType(for path: String) -> String {
    let ext = (path as NSString).pathExtension.lowercased()
    switch ext {
    case "json": return "application/json"
    case "js":   return "application/javascript"
    case "css":  return "text/css"
    case "html", "htm": return "text/html"
    case "xml":  return "application/xml"
    case "txt":  return "text/plain"
    case "svg":  return "image/svg+xml"
    case "png":  return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    default:     return "application/octet-stream"
    }
}

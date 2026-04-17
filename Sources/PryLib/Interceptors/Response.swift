import Foundation

/// Representa una respuesta HTTP producida por un interceptor o recibida desde el
/// servidor de destino. Value type NIO-agnóstico, simétrico a `RequestContext`.
public struct Response: Sendable {
    /// Status code HTTP (200, 403, 404, 500...).
    public var status: Int

    /// Headers de respuesta. Keys case-preserving.
    public var headers: [String: String]

    /// Body como `Data`. Para responses mockeadas suele ser pequeño; para responses
    /// forwarded desde servidor real puede ser grande — ver `BodyRef` en futuras
    /// iteraciones si aparece presión de memoria.
    public var body: Data?

    public init(status: Int, headers: [String: String] = [:], body: Data? = nil) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

// MARK: - Factories comunes

public extension Response {
    /// 403 Forbidden con body JSON de explicación. Usado típicamente por interceptors
    /// tipo BlockList o allowlists en phase `.gate`.
    static func forbidden(reason: String = "Blocked by Pry") -> Response {
        Response(
            status: 403,
            headers: ["Content-Type": "application/json"],
            body: Data(#"{"error":"\#(reason)"}"#.utf8)
        )
    }

    /// 200 OK con body JSON. Usado por interceptors de mocking.
    static func ok(json: String) -> Response {
        Response(
            status: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(json.utf8)
        )
    }

    /// 200 OK con body arbitrario.
    static func ok(body: Data, contentType: String = "application/octet-stream") -> Response {
        Response(
            status: 200,
            headers: ["Content-Type": contentType],
            body: body
        )
    }

    /// 404 Not Found vacío — útil para MapLocal cuando el archivo no existe.
    static func notFound() -> Response {
        Response(status: 404)
    }
}

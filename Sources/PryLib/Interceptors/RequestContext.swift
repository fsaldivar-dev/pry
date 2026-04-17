import Foundation

/// Representa una request HTTP que atraviesa el pipeline de interceptors de PryApp.
///
/// Value type intencionalmente NIO-agnóstico: los interceptors operan sobre este
/// contexto sin tener que conocer `HTTPRequestHead`, `ByteBuffer`, o cualquier otro
/// tipo de NIO. La traducción desde/hacia NIO vive en la capa de integración
/// (milestone 2, fuera del scope de Paso 1).
///
/// Un interceptor puede retornar `.transform(newCtx)` devolviendo una copia mutada
/// de este struct — como todos los campos son value types, mutations son seguras y
/// no afectan al caller.
public struct RequestContext: Sendable, Identifiable {
    /// Identificador único de la request durante su ciclo de vida en el pipeline.
    /// Se mantiene estable entre el request y la response.
    public let id: UUID

    /// Método HTTP en mayúsculas (`GET`, `POST`, `PUT`, etc.).
    public var method: String

    /// Host de destino sin scheme ni puerto (`api.example.com`).
    public var host: String

    /// Path + query string (`/v1/users?id=42`). No incluye host.
    public var path: String

    /// Puerto de destino. Default 443 para HTTPS, 80 para HTTP.
    public var port: Int

    /// Headers como diccionario case-preserving. Las keys se comparan case-insensitive
    /// en los interceptors que hagan matching semántico.
    public var headers: [String: String]

    /// Referencia opaca al body. `nil` para requests sin body (GET típico) o cuando
    /// el body aún no fue leído del stream. Ver `BodyRef` para el contrato de acceso.
    public var bodyRef: BodyRef?

    /// Timestamp de captura (cuando el proxy recibió la request).
    public let capturedAt: Date

    public init(
        id: UUID = UUID(),
        method: String,
        host: String,
        path: String,
        port: Int = 443,
        headers: [String: String] = [:],
        bodyRef: BodyRef? = nil,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.method = method
        self.host = host
        self.path = path
        self.port = port
        self.headers = headers
        self.bodyRef = bodyRef
        self.capturedAt = capturedAt
    }
}

/// Referencia a un body HTTP. El body real puede ser grande (MB), por lo que se
/// entrega por referencia — los consumidores piden el contenido on-demand con
/// `read()`. Evita copiar bodies cuando un interceptor sólo necesita headers.
public struct BodyRef: Sendable {
    /// Tamaño en bytes (conocido sin leer el body completo cuando es posible).
    public let contentLength: Int?

    /// Función asíncrona que entrega el body completo. Puede fallar si el body
    /// ya fue consumido o liberado (ej. request muy vieja ya evictada del store).
    public let read: @Sendable () async throws -> Data

    public init(contentLength: Int?, read: @escaping @Sendable () async throws -> Data) {
        self.contentLength = contentLength
        self.read = read
    }
}

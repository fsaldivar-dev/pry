import XCTest
@testable import PryLib

/// Semántica esperada de `.pause` en el chain executor (análogo a #140 para `.transform`).
///
/// El chain real vive en `HTTPInterceptor.executeChainAsync`; este test usa un helper
/// simétrico al loop real. Cualquier cambio al loop debe reflejarse también acá.
final class ChainPausePropagationTests: XCTestCase {

    /// Espejo del executor real. Debe cubrir:
    /// - `.pause` espera a que la resolution closure retorne, y luego encadena
    ///    el `InterceptResult` devuelto (pass/transform/shortCircuit).
    /// - Emite `RequestPausedEvent` al bus antes de awaitear la resolution.
    private func runChain(
        _ interceptors: [any Interceptor],
        on ctx: RequestContext,
        bus: EventBus? = nil
    ) async -> (Response?, RequestContext) {
        var current = ctx
        for interceptor in interceptors.sorted(by: { $0.phase < $1.phase }) {
            var result = await interceptor.intercept(current)
            // Desenrollar .pause encadenando la resolution.
            while case .pause(let resolution) = result {
                if let bus = bus {
                    await bus.publish(RequestPausedEvent(requestID: current.id))
                }
                result = await resolution()
            }
            switch result {
            case .pass:
                continue
            case .transform(let newCtx):
                current = newCtx
            case .shortCircuit(let response):
                return (response, current)
            case .pause:
                continue // inalcanzable — el while de arriba ya lo desenrolló.
            }
        }
        return (nil, current)
    }

    private func makeCtx() -> RequestContext {
        RequestContext(
            method: "GET",
            host: "example.com",
            path: "/api",
            port: 443,
            headers: ["Content-Type": "application/json"]
        )
    }

    // MARK: - pause awaitea la resolution

    func test_pause_resolutionPass_continuesChain() async {
        let pauser = FakeInterceptor(phase: .gate) { _ in
            .pause(resolution: { .pass })
        }
        let nextCalled = BoolBox()
        let next = FakeInterceptor(phase: .network) { _ in
            nextCalled.set(true); return .pass
        }
        let (response, _) = await runChain([pauser, next], on: makeCtx())
        XCTAssertNil(response)
        XCTAssertTrue(nextCalled.get(), "chain debió continuar después de .pause → .pass")
    }

    func test_pause_resolutionTransform_propagatesMutation() async {
        let pauser = FakeInterceptor(phase: .gate) { ctx in
            .pause(resolution: {
                var mutated = ctx
                mutated.headers["X-Paused"] = "yes"
                return .transform(mutated)
            })
        }
        let seenHeader = StringBox()
        let next = FakeInterceptor(phase: .transform) { ctx in
            seenHeader.set(ctx.headers["X-Paused"] ?? "")
            return .pass
        }
        let (_, finalCtx) = await runChain([pauser, next], on: makeCtx())
        XCTAssertEqual(seenHeader.get(), "yes", "transform post-pause debe ser visible al siguiente interceptor")
        XCTAssertEqual(finalCtx.headers["X-Paused"], "yes")
    }

    func test_pause_resolutionShortCircuit_stopsChain() async {
        let pauser = FakeInterceptor(phase: .gate) { _ in
            .pause(resolution: { .shortCircuit(.forbidden()) })
        }
        let laterCalled = BoolBox()
        let later = FakeInterceptor(phase: .network) { _ in
            laterCalled.set(true); return .pass
        }
        let (response, _) = await runChain([pauser, later], on: makeCtx())
        XCTAssertEqual(response?.status, 403)
        XCTAssertFalse(laterCalled.get(), "shortCircuit desde resolution debe cortar el chain")
    }

    func test_pause_afterTransform_seesPreviousMutation() async {
        let pre = FakeInterceptor(phase: .gate) { ctx in
            var mutated = ctx
            mutated.path = "/mutated-pre"
            return .transform(mutated)
        }
        let seenPath = StringBox()
        let pauser = FakeInterceptor(phase: .transform) { ctx in
            seenPath.set(ctx.path)
            return .pause(resolution: { .pass })
        }
        _ = await runChain([pre, pauser], on: makeCtx())
        XCTAssertEqual(seenPath.get(), "/mutated-pre", "pause debe ver mutaciones acumuladas por interceptors previos")
    }

    func test_pause_emitsRequestPausedEvent() async {
        let bus = EventBus()
        let pauser = FakeInterceptor(phase: .gate) { _ in
            .pause(resolution: { .pass })
        }
        let received = UUIDBox()
        let expectation = XCTestExpectation(description: "RequestPausedEvent recibido")
        let task = Task {
            for await event in bus.subscribe(to: RequestPausedEvent.self) {
                received.set(event.requestID)
                expectation.fulfill()
                break
            }
        }
        // Pequeño yield para que el subscriber esté registrado antes de publish.
        try? await Task.sleep(nanoseconds: 50_000_000)

        let ctx = makeCtx()
        _ = await runChain([pauser], on: ctx, bus: bus)

        await fulfillment(of: [expectation], timeout: 2.0)
        task.cancel()
        XCTAssertEqual(received.get(), ctx.id, "el evento debe llevar el id del RequestContext pausado")
    }
}

// MARK: - Sendable boxes

private final class StringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    func get() -> String { lock.withLock { value } }
    func set(_ v: String) { lock.withLock { value = v } }
}

private final class BoolBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func get() -> Bool { lock.withLock { value } }
    func set(_ v: Bool) { lock.withLock { value = v } }
}

private final class UUIDBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UUID?
    func get() -> UUID? { lock.withLock { value } }
    func set(_ v: UUID) { lock.withLock { value = v } }
}

// MARK: - test helper

private struct FakeInterceptor: Interceptor {
    let phase: Phase
    let handler: @Sendable (RequestContext) -> InterceptResult

    func intercept(_ ctx: RequestContext) async -> InterceptResult {
        handler(ctx)
    }
}

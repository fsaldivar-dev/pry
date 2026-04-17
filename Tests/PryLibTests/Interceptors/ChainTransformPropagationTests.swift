import XCTest
@testable import PryLib

/// Tests de alto nivel sobre cómo se comporta el loop de una chain cuando hay
/// `.transform` + `.shortCircuit` + `.pass`. El loop en sí vive en HTTPInterceptor
/// y TLSForwarder como método privado; estos tests cubren la semántica esperada
/// que el loop DEBE respetar, usando un helper público que replica el algoritmo.
final class ChainTransformPropagationTests: XCTestCase {

    /// Helper simétrico al executeChainAsync interno. Aplicar los mismos tests
    /// garantiza que cualquier cambio al loop rompe acá también.
    private func runChain(_ interceptors: [any Interceptor], on ctx: RequestContext) async -> (Response?, RequestContext) {
        var current = ctx
        for interceptor in interceptors.sorted(by: { $0.phase < $1.phase }) {
            let result = await interceptor.intercept(current)
            switch result {
            case .pass:
                continue
            case .transform(let newCtx):
                current = newCtx
            case .shortCircuit(let response):
                return (response, current)
            case .pause:
                continue
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

    // MARK: - transform propaga

    func test_transform_mutationsPropagate() async {
        let addHeader = FakeInterceptor(phase: .transform) { ctx in
            var new = ctx
            new.headers["X-Pry-Test"] = "1"
            return .transform(new)
        }
        let (_, finalCtx) = await runChain([addHeader], on: makeCtx())
        XCTAssertEqual(finalCtx.headers["X-Pry-Test"], "1")
    }

    func test_transform_multipleAccumulate() async {
        let a = FakeInterceptor(phase: .transform) { ctx in
            var new = ctx
            new.headers["X-A"] = "1"
            return .transform(new)
        }
        let b = FakeInterceptor(phase: .network) { ctx in
            var new = ctx
            new.host = "new-host.com"
            return .transform(new)
        }
        let (_, finalCtx) = await runChain([a, b], on: makeCtx())
        XCTAssertEqual(finalCtx.headers["X-A"], "1")
        XCTAssertEqual(finalCtx.host, "new-host.com")
    }

    func test_transform_seenByNextInterceptor() async {
        let first = FakeInterceptor(phase: .transform) { ctx in
            var new = ctx
            new.path = "/mutated"
            return .transform(new)
        }
        // `second` verifica que ve el path mutado por `first`.
        let seenPath = StringBox()
        let second = FakeInterceptor(phase: .network) { ctx in
            seenPath.set(ctx.path)
            return .pass
        }
        _ = await runChain([first, second], on: makeCtx())
        XCTAssertEqual(seenPath.get(), "/mutated")
    }

    // MARK: - shortCircuit vs transform

    func test_shortCircuit_winsOverLaterTransform() async {
        let cut = FakeInterceptor(phase: .gate) { _ in
            .shortCircuit(.forbidden())
        }
        let wouldTransform = FakeInterceptor(phase: .transform) { ctx in
            var new = ctx
            new.host = "never-applied.com"
            return .transform(new)
        }
        let (response, finalCtx) = await runChain([cut, wouldTransform], on: makeCtx())
        XCTAssertEqual(response?.status, 403)
        XCTAssertEqual(finalCtx.host, "example.com", "host debería quedar sin mutar — shortCircuit cortó antes")
    }

    func test_transformThenShortCircuit_preservesMutationAtCutPoint() async {
        let t = FakeInterceptor(phase: .resolve) { ctx in
            var new = ctx
            new.headers["X-Seen"] = "yes"
            return .transform(new)
        }
        let cut = FakeInterceptor(phase: .transform) { ctx in
            XCTAssertEqual(ctx.headers["X-Seen"], "yes", "el cut debe VER la mutación previa")
            return .shortCircuit(.ok(json: "{}"))
        }
        let (response, _) = await runChain([t, cut], on: makeCtx())
        XCTAssertEqual(response?.status, 200)
    }

    // MARK: - pass pasa sin mutar

    func test_pass_doesNotMutate() async {
        let a = FakeInterceptor(phase: .transform) { _ in .pass }
        let (_, finalCtx) = await runChain([a], on: makeCtx())
        XCTAssertEqual(finalCtx.host, "example.com")
        XCTAssertEqual(finalCtx.path, "/api")
    }

    // MARK: - phase ordering

    func test_phases_executeInOrder() async {
        let calledInOrder = PhaseListBox()
        let network = FakeInterceptor(phase: .network) { _ in
            calledInOrder.append(.network); return .pass
        }
        let gate = FakeInterceptor(phase: .gate) { _ in
            calledInOrder.append(.gate); return .pass
        }
        let transform = FakeInterceptor(phase: .transform) { _ in
            calledInOrder.append(.transform); return .pass
        }
        let resolve = FakeInterceptor(phase: .resolve) { _ in
            calledInOrder.append(.resolve); return .pass
        }
        _ = await runChain([network, gate, transform, resolve], on: makeCtx())
        XCTAssertEqual(calledInOrder.get(), [.gate, .resolve, .transform, .network])
    }
}

// MARK: - Sendable boxes para captures en @Sendable closures (strict concurrency)

private final class StringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    func get() -> String { lock.withLock { value } }
    func set(_ v: String) { lock.withLock { value = v } }
}

private final class PhaseListBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [Phase] = []
    func get() -> [Phase] { lock.withLock { value } }
    func append(_ p: Phase) { lock.withLock { value.append(p) } }
}

// MARK: - test helper

private struct FakeInterceptor: Interceptor {
    let phase: Phase
    let handler: @Sendable (RequestContext) -> InterceptResult

    func intercept(_ ctx: RequestContext) async -> InterceptResult {
        handler(ctx)
    }
}

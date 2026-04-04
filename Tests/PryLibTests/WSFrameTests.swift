import XCTest
@testable import PryLib

final class WSFrameTests: XCTestCase {
    func testTextFramePayload() {
        let frame = WSFrame(
            direction: .clientToServer,
            opcode: .text,
            payload: "hello".data(using: .utf8)!
        )
        XCTAssertEqual(frame.payloadText, "hello")
        XCTAssertEqual(frame.direction.rawValue, "↑")
        XCTAssertEqual(frame.opcode.label, "text")
        XCTAssertTrue(frame.isFinal)
    }

    func testBinaryFramePayload() {
        let data = Data([0x00, 0x01, 0x02, 0xFF])
        let frame = WSFrame(
            direction: .serverToClient,
            opcode: .binary,
            payload: data
        )
        XCTAssertEqual(frame.payload, data)
        XCTAssertEqual(frame.direction.rawValue, "↓")
        XCTAssertEqual(frame.opcode.label, "binary")
    }

    func testControlFrameLabels() {
        XCTAssertEqual(WSFrame.Opcode.close.label, "close")
        XCTAssertEqual(WSFrame.Opcode.ping.label, "ping")
        XCTAssertEqual(WSFrame.Opcode.pong.label, "pong")
        XCTAssertEqual(WSFrame.Opcode.continuation.label, "continuation")
        XCTAssertEqual(WSFrame.Opcode.unknown.label, "unknown")
    }

    func testOpcodeFromRawValue() {
        XCTAssertEqual(WSFrame.Opcode(rawValue: 0x1), .text)
        XCTAssertEqual(WSFrame.Opcode(rawValue: 0x2), .binary)
        XCTAssertEqual(WSFrame.Opcode(rawValue: 0x8), .close)
        XCTAssertEqual(WSFrame.Opcode(rawValue: 0x9), .ping)
        XCTAssertEqual(WSFrame.Opcode(rawValue: 0xA), .pong)
        XCTAssertNil(WSFrame.Opcode(rawValue: 0x3))
    }

    func testWebSocketRequestStore() {
        let store = RequestStore.shared
        store.clear()

        let id = store.addRequest(
            method: "GET",
            url: "/ws",
            host: "echo.websocket.org",
            appIcon: "🔌",
            appName: "ws",
            headers: [],
            body: nil
        )
        store.markWebSocket(id: id)

        let frame = WSFrame(direction: .clientToServer, opcode: .text, payload: "test".data(using: .utf8)!)
        store.addWSFrame(requestId: id, frame: frame)

        let req = store.get(id: id)
        XCTAssertNotNil(req)
        XCTAssertTrue(req!.isWebSocket)
        XCTAssertEqual(req!.wsFrames.count, 1)
        XCTAssertEqual(req!.wsFrames[0].payloadText, "test")

        store.clear()
    }
}

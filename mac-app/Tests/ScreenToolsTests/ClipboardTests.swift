import AppKit
import XCTest
@testable import ScreenTools

@MainActor
private final class StubPasteboard: TextPasteboard {
    var content: String?
    var denied = false
    func readText() throws -> String? {
        if denied { throw ClipboardFailure.denied }
        return content
    }
    func writeText(_ text: String) throws {
        if denied { throw ClipboardFailure.denied }
        content = text
    }
}

@MainActor
final class ClipboardTests: XCTestCase {
    func testComputerReadWriteNoTextAndPermissionPreserveDraft() {
        let board = StubPasteboard()
        let controller = ClipboardController(manager: DeviceManager(), pasteboard: board)
        for value in ["", "中文 🧪\n'引号' \"双引号\"\nhttps://example.com/?a=1&b=2", String(repeating: "长文本", count: 5000)] {
            controller.text = value
            controller.writeComputer()
            XCTAssertEqual(board.content, value)
            controller.text = "changed"
            controller.readComputer()
            XCTAssertEqual(controller.text, value)
            XCTAssertNil(controller.lastError)
        }
        board.content = nil
        controller.text = "保留草稿"
        controller.readComputer()
        XCTAssertEqual(controller.text, "保留草稿")
        XCTAssertNotNil(controller.lastError)
        board.denied = true
        controller.readComputer()
        XCTAssertEqual(controller.text, "保留草稿")
        XCTAssertEqual(controller.lastError, ClipboardFailure.denied.localizedDescription)
        controller.writeComputer()
        XCTAssertEqual(controller.lastError, ClipboardFailure.denied.localizedDescription)
    }

    func testNativePasteboardTextURLAndImageOnly() throws {
        // 命名剪贴板不读取或覆盖用户的系统剪贴板。
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let adapter = MacTextPasteboard(board)
        for text in ["", "Hello 中文 👋\nhttps://example.com"] {
            try adapter.writeText(text)
            XCTAssertEqual(try adapter.readText(), text)
        }
        board.clearContents()
        board.setString("https://example.com/路径", forType: .URL)
        XCTAssertEqual(try adapter.readText(), "https://example.com/路径")
        board.clearContents()
        board.setData(Data([1, 2, 3]), forType: .png)
        XCTAssertNil(try adapter.readText())
    }

    func testProtocolUTF8LengthEmptyAndBoundary() throws {
        XCTAssertEqual(ScrcpyClipboardProtocol.get, Data([8, 0]))
        let value = "中文🧪\n'\""
        let packet = try ScrcpyClipboardProtocol.set(value, sequence: 42)
        XCTAssertEqual(packet.first, 9)
        XCTAssertEqual(ScrcpyClipboardProtocol.integer(packet.subdata(in: 1..<9)), 42)
        XCTAssertEqual(packet[9], 0) // 不粘贴
        XCTAssertEqual(ScrcpyClipboardProtocol.integer(packet.subdata(in: 10..<14)), UInt64(value.utf8.count))
        XCTAssertEqual(String(data: packet.dropFirst(14), encoding: .utf8), value)
        XCTAssertEqual(try ScrcpyClipboardProtocol.set("", sequence: 1).count, 14)
        let max = String(repeating: "a", count: ScrcpyClipboardProtocol.maxTextBytes)
        XCTAssertEqual(try ScrcpyClipboardProtocol.set(max, sequence: 1).count, 1 << 18)
        XCTAssertThrowsError(try ScrcpyClipboardProtocol.set(max + "🧪", sequence: 1))
    }

    func testSocketRoundTripWithFragmentedMessages() async throws {
        for text in ["", "中文 👋\n'quotes' \"double\" https://example.com", String(repeating: "长文🧪", count: 1000)] {
            let peer = try ClipboardPeer(mode: "normal")
            defer { peer.stop() }
            let socket = ClipboardSocket(port: peer.port)
            defer { socket.close() }
            try await socket.open()
            let handshake = try await socket.receive(1)
            XCTAssertEqual(handshake, Data([0]))
            try await socket.setClipboard(text)
            let result = try await socket.clipboardText()
            XCTAssertEqual(result, text)
        }
    }

    func testAckDoesNotProveSuccessfulWrite() async throws {
        let peer = try ClipboardPeer(mode: "mismatch")
        defer { peer.stop() }
        let socket = ClipboardSocket(port: peer.port)
        defer { socket.close() }
        try await socket.open()
        _ = try await socket.receive(1)
        do {
            try await socket.setClipboard("new text")
            XCTFail("ACK 之后必须读回验证")
        } catch ClipboardFailure.verification { }
    }

    func testBridgeLaunchFlagsAndCleanup() async throws {
        let peer = try ClipboardPeer(mode: "bridge")
        defer { peer.stop() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let adb = directory.appendingPathComponent("adb")
        let log = directory.appendingPathComponent("commands")
        let server = directory.appendingPathComponent("server")
        try Data([1]).write(to: server)
        let script = """
        #!/bin/bash
        [ "$1" = "-s" ] && shift 2
        printf '%s\\n' "$*" >> '\(log.path)'
        case "$1" in
          forward) [ "$2" = "tcp:0" ] && echo \(peer.port); exit 0 ;;
          shell) case "$2" in *app_process*) exec /bin/sleep 30 ;; esac ;;
        esac
        exit 0
        """
        try script.write(to: adb, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adb.path)
        let previous = ProcessInfo.processInfo.environment["SCREENTOOLS_SCRCPY_SERVER"]
        setenv("SCREENTOOLS_SCRCPY_SERVER", server.path, 1)
        defer {
            if let previous { setenv("SCREENTOOLS_SCRCPY_SERVER", previous, 1) }
            else { unsetenv("SCREENTOOLS_SCRCPY_SERVER") }
        }
        let bridge = AndroidClipboardBridge()
        defer { bridge.stop() }
        let text = "text must never enter argv 中文🧪"
        _ = try await bridge.perform(adb: adb, serial: "TEST", writing: text)
        let commands = try String(contentsOf: log)
        XCTAssertTrue(commands.contains("video=false audio=false"))
        XCTAssertTrue(commands.contains("clipboard_autosync=false"))
        XCTAssertTrue(commands.contains("power_on=false"))
        XCTAssertTrue(commands.contains("forward --remove tcp:\(peer.port)"))
        XCTAssertTrue(commands.contains("kill \"$clip_pid\""))
        XCTAssertTrue(commands.contains("rm -f"))
        XCTAssertFalse(commands.contains(text))
    }

    func testDisconnectMalformedLengthAndTimeout() async throws {
        for mode in ["disconnect", "badlength", "stall"] {
            let peer = try ClipboardPeer(mode: mode)
            defer { peer.stop() }
            let socket = ClipboardSocket(port: peer.port)
            defer { socket.close() }
            try await socket.open()
            _ = try await socket.receive(1)
            do {
                if mode == "stall" { _ = try await socket.receive(1, timeout: 0.05) }
                else { _ = try await socket.clipboardText() }
                XCTFail("应当检测到 \(mode)")
            } catch {
                let expected: ClipboardFailure = mode == "stall" ? .timeout : (mode == "badlength" ? .protocolError : .disconnected)
                XCTAssertEqual(error.localizedDescription, expected.localizedDescription)
            }
        }
    }

    func testMissingTextResponseIsExplicitTimeoutNotEmptyClipboard() async throws {
        let peer = try ClipboardPeer(mode: "stall")
        defer { peer.stop() }
        let socket = ClipboardSocket(port: peer.port)
        defer { socket.close() }
        try await socket.open()
        _ = try await socket.receive(1)
        do {
            _ = try await socket.clipboardText(timeout: 0.05)
            XCTFail("无响应不能视为空字符串或成功读取")
        } catch ClipboardFailure.textResponseTimeout {
            XCTAssertTrue(ClipboardFailure.textResponseTimeout.localizedDescription.contains("读取超时"))
        }
    }
}

/// 本地 TCP 对端模拟 scrcpy 协议；不访问 Android，也不使用系统剪贴板。
private final class ClipboardPeer {
    let process = Process()
    let port: UInt16

    init(mode: String) throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", "-c", Self.source, mode]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        var bytes = Data()
        while bytes.count < 8 {
            let byte = output.fileHandleForReading.readData(ofLength: 1)
            if byte.isEmpty || byte == Data([10]) { break }
            bytes.append(byte)
        }
        guard let port = UInt16(String(decoding: bytes, as: UTF8.self)) else {
            if process.isRunning { process.terminate() }
            throw ClipboardFailure.protocolError
        }
        self.port = port
    }

    func stop() { if process.isRunning { process.terminate() } }
    deinit { stop() }

    static let source = #"""
import socket, struct, sys, time
s = socket.socket()
s.bind(('127.0.0.1', 0))
s.listen(1)
print(s.getsockname()[1], flush=True)
s.settimeout(10)
c, _ = s.accept()
c.settimeout(10)
mode = sys.argv[1]
if mode == 'bridge': time.sleep(0.1)
c.sendall(b'\0')
text = b'original'
def read(n):
    data = b''
    while len(data) < n:
        b = c.recv(n-len(data))
        if not b: raise EOFError()
        data += b
    return data
def send(data):
    for i in range(0, len(data), 3): c.sendall(data[i:i+3])
try:
    while True:
        kind = read(1)[0]
        if mode == 'disconnect': break
        if mode == 'stall': time.sleep(10); break
        if kind == 8:
            read(1)
            if mode == 'badlength': send(b'\0' + struct.pack('>I', 0xffffffff)); break
            send(b'\0' + struct.pack('>I', len(text)) + text)
        elif kind == 9:
            seq = read(8)
            assert read(1) == b'\0'
            length = struct.unpack('>I', read(4))[0]
            incoming = read(length)
            if mode != 'mismatch': text = incoming
            send(b'\1' + seq)
except (EOFError, OSError): pass
finally:
    c.close()
    s.close()
"""#
}

import Foundation
import Network

/// scrcpy v5.0.1 控制协议。只发送剪贴板消息，不注入按键。
enum ScrcpyClipboardProtocol {
    static let version = "5.0.1"
    static let maxTextBytes = (1 << 18) - 14
    static let get = Data([8, 0]) // GET_CLIPBOARD, COPY_KEY_NONE

    static func set(_ text: String, sequence: UInt64) throws -> Data {
        let bytes = Data(text.utf8)
        guard bytes.count <= maxTextBytes else { throw ClipboardFailure.tooLarge }
        var message = Data([9])
        append(sequence, to: &message)
        message.append(0) // paste=false
        append(UInt32(bytes.count), to: &message)
        message.append(bytes)
        return message
    }

    static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var value = value.bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    static func integer(_ bytes: Data) -> UInt64 {
        bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }
}

/// 所有 Network 回调在主队列执行；每次请求都带截止时间，取消连接会解除挂起的读取。
@MainActor
final class ClipboardSocket {
    private let connection: NWConnection

    init(port: UInt16) {
        connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    }

    func close() { connection.cancel() }

    private func request<T>(
        timeout: TimeInterval,
        _ start: (@escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            var finished = false
            var timer: DispatchWorkItem?
            let finish: (Result<T, Error>) -> Void = { result in
                MainActor.assumeIsolated {
                    guard !finished else { return }
                    finished = true
                    timer?.cancel()
                    continuation.resume(with: result)
                }
            }
            let deadline = DispatchWorkItem { [weak self] in
                finish(.failure(ClipboardFailure.timeout))
                self?.close()
            }
            timer = deadline
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, timeout), execute: deadline)
            start(finish)
        }
    }

    func open(timeout: TimeInterval = 2) async throws {
        let _: Void = try await request(timeout: timeout) { finish in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(.success(()))
                case .failed, .cancelled: finish(.failure(ClipboardFailure.disconnected))
                default: break
                }
            }
            connection.start(queue: .main)
        }
    }

    func send(_ data: Data) async throws {
        let _: Void = try await request(timeout: 5) { finish in
            connection.send(content: data, completion: .contentProcessed { error in
                finish(error == nil ? .success(()) : .failure(ClipboardFailure.disconnected))
            })
        }
    }

    func receive(_ count: Int, timeout: TimeInterval = 5) async throws -> Data {
        var result = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while result.count < count {
            let remaining = count - result.count
            let data: Data = try await request(timeout: deadline.timeIntervalSinceNow) { finish in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, complete, error in
                    if let data, !data.isEmpty { finish(.success(data)) }
                    else if error != nil || complete { finish(.failure(ClipboardFailure.disconnected)) }
                    else { finish(.failure(ClipboardFailure.protocolError)) }
                }
            }
            result.append(data)
        }
        return result
    }

    func clipboardText(timeout: TimeInterval = 5) async throws -> String {
        try await send(ScrcpyClipboardProtocol.get)
        let type: Data
        do { type = try await receive(1, timeout: timeout) }
        catch ClipboardFailure.timeout { throw ClipboardFailure.textResponseTimeout }
        guard type == Data([0]) else { throw ClipboardFailure.protocolError }
        let length = Int(ScrcpyClipboardProtocol.integer(try await receive(4)))
        guard length <= (1 << 18) - 5 else { throw ClipboardFailure.protocolError }
        guard length <= ScrcpyClipboardProtocol.maxTextBytes else { throw ClipboardFailure.tooLarge }
        let bytes = try await receive(length)
        guard let text = String(data: bytes, encoding: .utf8) else { throw ClipboardFailure.protocolError }
        return text
    }

    func setClipboard(_ text: String) async throws {
        let sequence: UInt64 = 1
        try await send(ScrcpyClipboardProtocol.set(text, sequence: sequence))
        guard try await receive(1) == Data([1]),
              ScrcpyClipboardProtocol.integer(try await receive(8)) == sequence else {
            throw ClipboardFailure.protocolError
        }
        // scrcpy 即使 setPrimaryClip 失败也可能 ACK，所以核对实际内容。
        guard try await clipboardText() == text else { throw ClipboardFailure.verification }
    }
}

/// 手动操作使用短时会话；一次操作完成就关闭 socket、服务进程和 ADB 转发。
@MainActor
final class AndroidClipboardBridge {
    private var process: Process?
    private var socket: ClipboardSocket?
    @MainActor private struct Cleanup {
        let adb: URL
        let prefix: [String]
        let remote: String
        var port: UInt16?

        var commands: [[String]] {
            let pidPath = AndroidProvider.shellQuote(remote + ".pid")
            let script = "if [ -f \(pidPath) ]; then read -r clip_pid < \(pidPath); "
                + "case \"$clip_pid\" in ''|*[!0-9]*) ;; *) kill \"$clip_pid\" 2>/dev/null ;; esac; fi; "
                + "rm -f \(pidPath) \(AndroidProvider.shellQuote(remote))"
            return (port.map { [prefix + ["forward", "--remove", "tcp:\($0)"]] } ?? [])
                + [prefix + ["shell", script]]
        }
    }
    private var cleanupArguments: Cleanup?
    private var stopped = false

    /// 退出应用时也能清理：无需等待 Swift Task 再获得执行机会。
    func stop() {
        stopped = true
        socket?.close()
        socket = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        if let descriptor = cleanupArguments {
            for arguments in descriptor.commands {
                let cleanup = Process()
                cleanup.executableURL = descriptor.adb
                cleanup.arguments = arguments
                cleanup.standardInput = FileHandle.nullDevice
                cleanup.standardOutput = FileHandle.nullDevice
                cleanup.standardError = FileHandle.nullDevice
                try? cleanup.run()
            }
            cleanupArguments = nil
        }
    }

    func perform(adb: URL, serial: String, writing text: String? = nil) async throws -> String? {
        guard process == nil, cleanupArguments == nil else { throw ShotFailure("剪贴板操作正在进行，请稍候") }
        if let text { _ = try ScrcpyClipboardProtocol.set(text, sequence: 1) }
        stopped = false
        let env = ProcessInfo.processInfo.environment
        let server = env["SCREENTOOLS_SCRCPY_SERVER"].map { URL(fileURLWithPath: $0) }
            ?? Bundle.main.resourceURL!.appendingPathComponent("scrcpy-server-v\(ScrcpyClipboardProtocol.version)")
        guard FileManager.default.fileExists(atPath: server.path) else {
            throw ShotFailure("缺少 Android 剪贴板组件，请重新构建或安装完整的屏幕工具箱")
        }
        let remote = "/data/local/tmp/screentools-clipboard-\(UUID().uuidString).jar"
        let prefix = ["-s", serial]
        cleanupArguments = Cleanup(adb: adb, prefix: prefix, remote: remote)
        var port: UInt16?
        do {
            _ = try await command(adb, prefix + ["push", server.path, remote])
            let scid = UInt32.random(in: 1...0x7fffffff)
            let name = String(format: "scrcpy_%08x", scid)
            let output = try await command(adb, prefix + ["forward", "tcp:0", "localabstract:\(name)"])
            guard let assigned = UInt16(output.trimmingCharacters(in: .whitespacesAndNewlines)), assigned != 0 else {
                throw ClipboardFailure.protocolError
            }
            port = assigned
            cleanupArguments?.port = assigned
            guard !stopped else { throw ClipboardFailure.disconnected }
            let proc = Process()
            proc.executableURL = adb
            proc.arguments = prefix + ["shell", "echo $$ > \(AndroidProvider.shellQuote(remote + ".pid")); "
                + "CLASSPATH=\(AndroidProvider.shellQuote(remote)) exec app_process / "
                + "com.genymobile.scrcpy.Server \(ScrcpyClipboardProtocol.version) scid=\(String(scid, radix: 16)) "
                + "video=false audio=false control=true tunnel_forward=true clipboard_autosync=false "
                + "send_device_meta=false power_on=false cleanup=true log_level=warn"]
            proc.standardInput = FileHandle.nullDevice
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try proc.run()
            process = proc
            let deadline = Date().addingTimeInterval(10)
            var connected: ClipboardSocket?
            while Date() < deadline, !stopped, proc.isRunning {
                let channel = ClipboardSocket(port: assigned)
                socket = channel
                do {
                    try await channel.open()
                    guard try await channel.receive(1, timeout: 1) == Data([0]) else {
                        throw ClipboardFailure.protocolError
                    }
                    connected = channel
                    break
                } catch {
                    channel.close()
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            guard let channel = connected, !stopped else { throw ClipboardFailure.disconnected }
            let result: String?
            if let text {
                try await channel.setClipboard(text)
                result = nil
            } else {
                result = try await channel.clipboardText()
            }
            await clean(adb: adb, prefix: prefix, port: port, remote: remote)
            return result
        } catch {
            await clean(adb: adb, prefix: prefix, port: port, remote: remote)
            throw error
        }
    }

    private func command(_ adb: URL, _ args: [String]) async throws -> String {
        let output = try await ProcessRunner.run(adb, args, timeout: 15)
        guard !stopped else { throw ClipboardFailure.disconnected }
        guard !output.timedOut else { throw ClipboardFailure.timeout }
        guard output.status == 0 else {
            throw ShotFailure(AndroidProvider.problem(forError: output.stderrText) ?? "无法连接 Android 剪贴板组件，请确认 USB 调试授权和设备连接")
        }
        return output.stdoutText
    }

    private func clean(adb: URL, prefix: [String], port: UInt16?, remote: String) async {
        socket?.close()
        socket = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        for arguments in Cleanup(adb: adb, prefix: prefix, remote: remote, port: port).commands {
            _ = try? await ProcessRunner.run(adb, arguments, timeout: 3)
        }
        cleanupArguments = nil
    }
}

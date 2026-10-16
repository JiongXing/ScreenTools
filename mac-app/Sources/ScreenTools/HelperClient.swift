import Foundation

/// 管理常驻的 Python 辅助进程（ios_helper.py），通过 stdin/stdout 按行收发 JSON。
@MainActor
final class HelperClient {
    typealias Reply = [String: Any]

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<Reply, Never>] = [:]
    private var timers: [Int: DispatchWorkItem] = [:]
    private var stopping = false
    private var recentCrashes: [Date] = []

    /// 打包后的 App 用 Contents/Resources 下的内置 Python；开发时可用环境变量覆盖。
    private var pythonURL: URL {
        if let path = ProcessInfo.processInfo.environment["SCREENTOOLS_PYTHON"] {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.resourceURL!.appendingPathComponent("python/bin/python3")
    }

    private var scriptURL: URL {
        if let path = ProcessInfo.processInfo.environment["SCREENTOOLS_HELPER"] {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.resourceURL!.appendingPathComponent("helper/ios_helper.py")
    }

    func start() {
        stopping = false
        guard process == nil else { return }

        let proc = Process()
        proc.executableURL = pythonURL
        // -I 隔离用户环境，-B 不写 .pyc（避免破坏 App 签名）
        proc.arguments = ["-I", "-B", scriptURL.path]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        proc.environment = env

        let input = Pipe()
        let output = Pipe()
        proc.standardInput = input
        proc.standardOutput = output
        proc.standardError = FileHandle.nullDevice // 辅助进程自己写日志文件

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                // EOF：辅助进程已退出，不摘掉 handler 会一直空转
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.consume(data) }
            }
        }
        proc.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handleExit(status: status) }
            }
        }

        do {
            try proc.run()
        } catch {
            AppLog.write("failed to launch helper: \(error)")
            return
        }
        process = proc
        stdinHandle = input.fileHandleForWriting
    }

    func stop() {
        stopping = true
        try? stdinHandle?.close() // 辅助进程读到 EOF 后会关闭隧道并退出
        stdinHandle = nil
        process?.terminate()
    }

    func send(_ cmd: String, _ params: [String: Any] = [:], timeout: TimeInterval) async -> Reply {
        if process == nil { start() }
        guard let stdinHandle else {
            return Self.failure("HELPER_DOWN", "截图组件启动失败")
        }
        let id = nextID
        nextID += 1
        var payload = params
        payload["id"] = id
        payload["cmd"] = cmd
        guard var line = try? JSONSerialization.data(withJSONObject: payload) else {
            return Self.failure("UNKNOWN", "请求编码失败")
        }
        line.append(0x0A)

        return await withCheckedContinuation { continuation in
            pending[id] = continuation
            do {
                try stdinHandle.write(contentsOf: line)
            } catch {
                resolve(id, Self.failure("HELPER_DOWN", "截图组件已退出，请重试"))
                return
            }
            let timer = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.handleTimeout(id) }
            }
            timers[id] = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timer)
        }
    }

    // MARK: - 内部

    private func resolve(_ id: Int, _ reply: Reply) {
        timers.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(returning: reply)
    }

    /// 请求超时：辅助进程仍在处理它（并占着内部锁），后续请求都会排在后面，所以直接重启辅助进程。
    private func handleTimeout(_ id: Int) {
        guard pending[id] != nil else { return }
        resolve(id, Self.failure("TIMEOUT", "操作超时，请确认手机已解锁并保持连接"))
        AppLog.write("request \(id) timed out, restarting helper")
        process?.terminate() // terminationHandler → handleExit 会自动重启
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? Reply,
                  let id = obj["id"] as? Int else { continue }
            resolve(id, obj)
        }
    }

    private func handleExit(status: Int32) {
        process = nil
        stdinHandle = nil
        buffer.removeAll()
        for id in Array(pending.keys) {
            resolve(id, Self.failure("HELPER_DOWN", "截图组件意外退出，请重试"))
        }
        guard !stopping else { return }

        // 自动重启；1 分钟内崩溃超过 5 次就不再自动拉起，等下次截图时再尝试
        AppLog.write("helper exited with status \(status)")
        let now = Date()
        recentCrashes = recentCrashes.filter { now.timeIntervalSince($0) < 60 } + [now]
        guard recentCrashes.count <= 5 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated { self?.start() }
        }
    }

    private static func failure(_ code: String, _ message: String) -> Reply {
        ["ok": false, "code": code, "message": message]
    }
}

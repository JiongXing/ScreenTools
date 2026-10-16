import Foundation

/// 在后台线程运行一个命令行程序，收集输出，超时则终止。
enum ProcessRunner {
    struct Output {
        let status: Int32
        let stdout: Data
        let stderr: Data
        let timedOut: Bool

        var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
        var stderrText: String { String(decoding: stderr, as: UTF8.self) }
    }

    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let timedOut = Flag()
                let killer = DispatchWorkItem {
                    timedOut.set()
                    process.terminate()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

                // stdout 和 stderr 并行读，避免其中一个管道写满后互相卡死
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                killer.cancel()

                continuation.resume(returning: Output(
                    status: process.terminationStatus, stdout: outData, stderr: errData, timedOut: timedOut.value
                ))
            }
        }
    }

    /// 运行但不收集输出（用于会派生常驻进程的命令，如 adb start-server）。
    static func runDetached(_ executable: URL, _ arguments: [String], timeout: TimeInterval) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else {
                    continuation.resume()
                    return
                }
                let killer = DispatchWorkItem { process.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                process.waitUntilExit()
                killer.cancel()
                continuation.resume()
            }
        }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        func set() { lock.lock(); flag = true; lock.unlock() }
        var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    }
}

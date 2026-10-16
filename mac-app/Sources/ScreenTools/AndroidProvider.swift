import Foundation

/// Android：调用 adb。优先使用用户已安装的 adb（避免两个版本的 adb 服务互相踢掉），
/// 找不到时用 App 内置的 Contents/Helpers/adb。
@MainActor
final class AndroidProvider: DeviceProvider {
    private struct Props {
        let name: String
        let model: String?
        let version: String?
    }

    private lazy var adb: URL? = Self.locateADB()
    private var serverStarted = false
    private var propsCache: [String: Props] = [:]

    var isAvailable: Bool { adb != nil }

    func devices(refresh: Bool) async -> [Device] {
        guard let adb else { return [] }
        await ensureServer(adb)
        guard let output = try? await ProcessRunner.run(adb, ["devices", "-l"], timeout: 10), output.status == 0 else {
            return []
        }

        var result: [Device] = []
        for entry in Self.parseDevices(output.stdoutText) {
            var device = Device(
                platform: .android,
                serial: entry.serial,
                name: entry.model?.replacingOccurrences(of: "_", with: " ") ?? "Android 手机",
                model: nil,
                osVersion: nil,
                connection: Self.isWireless(entry.serial) ? .wifi : .usb,
                problem: Self.problem(forState: entry.state)
            )
            if entry.state == "device" {
                if refresh || propsCache[entry.serial] == nil {
                    propsCache[entry.serial] = await readProps(adb, serial: entry.serial)
                }
            }
            if let props = propsCache[entry.serial] {
                device.name = props.name
                device.model = props.model
                device.osVersion = props.version
            }
            result.append(device)
        }
        return result
    }

    func screenshot(_ device: Device, to url: URL) async throws {
        guard let adb else { throw ShotFailure("没有找到 adb，无法连接 Android 手机") }
        await ensureServer(adb)

        // exec-out 原样传输二进制，-p 让手机直接输出 PNG
        let output = try await ProcessRunner.run(adb, ["-s", device.serial, "exec-out", "screencap", "-p"], timeout: 20)
        if output.timedOut {
            throw ShotFailure("截图超时：请确认手机已解锁并保持连接")
        }
        guard output.status == 0, output.stdout.starts(with: [0x89, 0x50, 0x4E, 0x47]) else {
            let message = (output.stderrText + output.stdoutText.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
            AppLog.write("screencap failed (\(output.status)): \(message)")
            throw ShotFailure(Self.problem(forError: message) ?? "截图失败：\(message.prefix(120))")
        }
        try output.stdout.write(to: url)
    }

    // MARK: - adb

    private func ensureServer(_ adb: URL) async {
        guard !serverStarted else { return }
        // adb 首次运行会派生常驻服务进程；单独启动它，避免服务进程继承输出管道导致读取卡住
        await ProcessRunner.runDetached(adb, ["start-server"], timeout: 15)
        serverStarted = true
    }

    private func readProps(_ adb: URL, serial: String) async -> Props? {
        let script = "getprop ro.product.marketname; getprop ro.product.model; getprop ro.build.version.release; "
            + "settings get global device_name"
        guard let output = try? await ProcessRunner.run(adb, ["-s", serial, "shell", script], timeout: 8),
              output.status == 0 else { return nil }
        let lines = output.stdoutText.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func line(_ i: Int) -> String? {
            guard i < lines.count, !lines[i].isEmpty, lines[i] != "null" else { return nil }
            return lines[i]
        }
        let model = line(0) ?? line(1)
        return Props(name: line(3) ?? model ?? "Android 手机", model: model, version: line(2))
    }

    static func locateADB() -> URL? {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let path = env["SCREENTOOLS_ADB"] { candidates.append(path) }
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let sdk = env[key] { candidates.append("\(sdk)/platform-tools/adb") }
        }
        candidates += [
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/adb").path,
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    // MARK: - 解析

    struct Entry: Equatable {
        let serial: String
        let state: String
        let model: String?
    }

    /// 解析 `adb devices -l`，例如：
    /// `R58M123ABC  device usb:1-1 product:a52q model:SM_A525F device:a52q transport_id:2`
    static func parseDevices(_ text: String) -> [Entry] {
        text.components(separatedBy: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("List of devices"), !line.hasPrefix("*") else { return nil }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { return nil }
            // 状态可能是两个词，如 "no permissions"
            var state = parts[1]
            if state == "no", parts.count > 2 { state = "no permissions" }
            let model = parts.first { $0.hasPrefix("model:") }.map { String($0.dropFirst("model:".count)) }
            return Entry(serial: parts[0], state: state, model: model)
        }
    }

    static func isWireless(_ serial: String) -> Bool {
        serial.contains("._adb-tls-connect.") || serial.range(of: #"^[\d.]+:\d+$"#, options: .regularExpression) != nil
    }

    static func problem(forState state: String) -> String? {
        switch state {
        case "device": return nil
        case "unauthorized": return "未授权：请解锁手机，在「允许 USB 调试吗？」弹窗中点「允许」"
        case "authorizing": return "正在授权，请稍候"
        case "offline": return "设备离线：请重新插拔数据线，或在手机上关闭再打开 USB 调试"
        case "recovery", "sideload", "bootloader", "rescue": return "手机不在正常系统模式（\(state)）"
        default: return "设备状态异常：\(state)"
        }
    }

    static func problem(forError text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("unauthorized") { return problem(forState: "unauthorized") }
        if lower.contains("offline") { return problem(forState: "offline") }
        if lower.contains("not found") { return "所选的 Android 手机已断开，请重新连接或在菜单中换一台设备" }
        return nil
    }
}

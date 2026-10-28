import AppKit

enum ClipboardFailure: LocalizedError {
    case noText, denied, disconnected, timeout, textResponseTimeout, protocolError, tooLarge, verification

    var errorDescription: String? {
        switch self {
        case .noText: return "未获取到文本，剪贴板可能为空、非文本或受系统限制；编辑内容已保留"
        case .denied: return "系统不允许读取剪贴板，请在系统设置中允许访问，或使用粘贴操作"
        case .disconnected: return "剪贴板连接已断开，请确认手机已解锁并重新连接"
        case .timeout: return "剪贴板操作超时，请确认手机已解锁并保持连接后重试"
        case .textResponseTimeout: return "读取超时，未获取到文本，可能为空、非文本或系统限制；编辑内容已保留，请确认手机已解锁并保持连接后重试"
        case .protocolError: return "剪贴板组件返回了无法识别的数据，请重新连接后重试"
        case .tooLarge: return "文本过长，Android 剪贴板单次最多支持 262130 字节 UTF-8 文本"
        case .verification: return "写入后未能核对到相同文本，手机可能限制了剪贴板访问；请检查手机后重试"
        }
    }
}

@MainActor
protocol TextPasteboard: AnyObject {
    func readText() throws -> String?
    func writeText(_ text: String) throws
}

@MainActor
final class MacTextPasteboard: TextPasteboard {
    private let pasteboard: NSPasteboard
    init(_ pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    func readText() throws -> String? {
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny {
            throw ClipboardFailure.denied
        }
        return pasteboard.string(forType: .string) ?? pasteboard.string(forType: .URL)
    }

    func writeText(_ text: String) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { throw ClipboardFailure.denied }
    }
}

/// 草稿只存在内存中。目标和写入文本在提交时捕获，不在异步操作后重新选择。
@MainActor
final class ClipboardController: ObservableObject {
    @Published var text = ""
    @Published private(set) var isBusy = false
    @Published private(set) var status: String?
    @Published private(set) var lastError: String?
    private let manager: DeviceManager
    private let pasteboard: TextPasteboard

    init(manager: DeviceManager, pasteboard: TextPasteboard? = nil) {
        self.manager = manager
        self.pasteboard = pasteboard ?? MacTextPasteboard()
    }

    func readComputer() {
        guard !isBusy else { return }
        lastError = nil
        status = nil
        do {
            guard let value = try pasteboard.readText() else { throw ClipboardFailure.noText }
            text = value
            status = "已读取电脑剪贴板"
        } catch { lastError = error.localizedDescription }
    }

    func writeComputer() {
        guard !isBusy else { return }
        lastError = nil
        status = nil
        do {
            try pasteboard.writeText(text)
            status = "已写入电脑剪贴板"
        } catch { lastError = error.localizedDescription }
    }

    func readPhone() async { await phoneOperation(writing: false) }
    func writePhone() async { await phoneOperation(writing: true) }

    private func phoneOperation(writing: Bool) async {
        guard !isBusy else { return }
        let target = manager.selectedKey.flatMap { key in manager.devices.first { $0.key == key } }
            ?? (manager.selectedKey == nil ? manager.autoChoice : nil)
        let value = text
        lastError = nil
        status = nil
        guard let device = target else {
            lastError = manager.selectedKey == nil ? manager.noDeviceMessage : "所选手机未连接，请重新连接或选择其它设备"
            return
        }
        isBusy = true
        status = "正在\(writing ? "写入" : "读取")「\(device.name)」剪贴板…"
        defer { isBusy = false }
        do {
            let provider = manager.provider(for: device)
            if writing {
                try await provider.writeClipboard(device, text: value)
            } else {
                guard let content = try await provider.readClipboard(device) else { throw ClipboardFailure.noText }
                text = content
            }
            status = "已\(writing ? "写入" : "读取")「\(device.name)」剪贴板"
        } catch {
            status = nil
            lastError = error.localizedDescription
            AppLog.write("clipboard \(writing ? "write" : "read") failed (\(device.platform.rawValue))")
        }
    }
}

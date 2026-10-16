import AppKit

/// 截图编排：选定设备 → 截图 → 保存到「下载」→ 复制到剪贴板 → 用预览打开。
@MainActor
final class ShotController: ObservableObject {
    private let manager: DeviceManager
    @Published private(set) var isBusy = false
    /// 最近几张截图（新的在前），供主窗口预览与历史使用
    @Published private(set) var history: [URL] = [] {
        didSet { Settings.historyPaths = history.map(\.path) }
    }
    /// 最近一次失败的原因；成功后清空
    @Published private(set) var lastError: String?
    var onBusyChange: ((Bool) -> Void)?

    init(manager: DeviceManager) {
        self.manager = manager
        history = Settings.historyPaths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    func take(_ format: ShotFormat) {
        guard !isBusy else { return } // 截图进行中，忽略重复按键
        setBusy(true)
        Task {
            defer { setBusy(false) }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("screentools-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: tmp) }

            do {
                lastError = nil
                let device = try await manager.target()
                try await manager.provider(for: device).screenshot(device, to: tmp)
                // JPEG 编码、读写文件、黑屏检测都放到后台，避免大屏 iPad 截图时卡住菜单栏
                let prefix = device.filePrefix
                let result = try await Task.detached(priority: .userInitiated) {
                    let url = try ImageOutput.save(pngAt: tmp, as: format, prefix: prefix)
                    let data = try Data(contentsOf: url)
                    return (url: url, data: data, blank: ImageOutput.looksBlank(url))
                }.value
                let url = result.url
                ImageOutput.copyToPasteboard(result.data, format: format)
                history = Array(([url] + history).prefix(8))
                if Self.openAfterCapture {
                    NSWorkspace.shared.open(url)
                }
                AppLog.write("saved \(url.lastPathComponent) from \(device.key)")
                if result.blank {
                    Notifier.warning(
                        title: "截图是全黑的",
                        body: "当前页面可能禁止截屏（如银行、支付、视频类 App），或手机处于息屏状态"
                    )
                }
            } catch {
                lastError = error.localizedDescription
                Notifier.failure(error.localizedDescription)
            }
        }
    }

    /// 截图后是否用默认看图程序（一般是「预览」）打开，默认关闭
    static var openAfterCapture: Bool {
        get { UserDefaults.standard.object(forKey: "openAfterCapture") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "openAfterCapture") }
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        onBusyChange?(busy)
    }
}

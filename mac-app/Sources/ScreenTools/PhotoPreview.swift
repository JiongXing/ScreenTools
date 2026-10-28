import AppKit
import QuickLookUI

/// 一次预览持有一次临时下载；失败、取消和窗口关闭都释放整个目录。
@MainActor
final class PhotoPreviewSession {
    nonisolated static let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScreenTools-PhotoPreviews", isDirectory: true)

    let directory: URL
    let urls: [URL]
    let failureCount: Int

    private init(directory: URL, urls: [URL], failureCount: Int) {
        self.directory = directory
        self.urls = urls
        self.failureCount = failureCount
    }

    static func prepare(
        _ items: [PhotoItem], device: Device, provider: DeviceProvider,
        root: URL = PhotoPreviewSession.root,
        onProgress: @MainActor (Int) -> Void
    ) async throws -> PhotoPreviewSession {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try Task.checkCancellation()
            let jobs = PhotoNaming.exportJobs(items, to: directory)
            let failures = try await provider.exportPhotos(device, jobs: jobs, onProgress: onProgress)
            // 底层取消在文件之间生效；最后一个文件下载时取消也不能打开窗口。
            try Task.checkCancellation()
            let urls = jobs.compactMap { job -> URL? in
                guard failures[job.item.id] == nil,
                      FileManager.default.fileExists(atPath: job.destination.path) else { return nil }
                return job.destination
            }
            guard !urls.isEmpty else {
                throw ShotFailure("无法预览：所选项均下载失败（\(failures.values.first ?? "未生成可预览的文件")）")
            }
            return PhotoPreviewSession(directory: directory, urls: urls, failureCount: jobs.count - urls.count)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }

    deinit { try? FileManager.default.removeItem(at: directory) }

    /// 只在应用启动时调用，清理上次异常退出留下的下载。
    static func cleanupStaleSessions() { try? FileManager.default.removeItem(at: root) }
}

/// 数据源必须在系统预览窗口打开期间保持存活。
@MainActor
final class PhotoPreviewController: NSObject, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var session: PhotoPreviewSession?
    private weak var panel: QLPreviewPanel?

    var hasItems: Bool { session != nil }

    func present(_ session: PhotoPreviewSession) throws {
        close()
        self.session = session
        guard let panel = QLPreviewPanel.shared() else {
            close()
            throw ShotFailure("无法打开系统预览窗口")
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.updateController()
        guard panel.dataSource === self else {
            AppLog.write("Quick Look controller unavailable: main=\(String(describing: NSApp.mainWindow)), key=\(String(describing: NSApp.keyWindow)), controller=\(String(describing: panel.currentController))")
            panel.orderOut(nil)
            close()
            throw ShotFailure("无法打开系统预览：请回到手机相册后重试")
        }
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
    }

    func beginControl(_ panel: QLPreviewPanel) {
        self.panel = panel
        panel.dataSource = self
        panel.delegate = self
    }

    func endControl(_ panel: QLPreviewPanel) {
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate === self { panel.delegate = nil }
        self.panel = nil
        session?.cleanup()
        session = nil
    }

    func close() {
        if let panel, panel.dataSource === self {
            panel.orderOut(nil)
            endControl(panel)
        }
        session?.cleanup()
        session = nil
    }

    func windowWillClose(_ notification: Notification) { close() }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { session?.urls.count ?? 0 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard let urls = session?.urls, urls.indices.contains(index) else { return nil }
        return urls[index] as NSURL
    }
}

/// 系统 Quick Look 经由主窗口响应链取得控制器，避免直接抢占全局预览面板。
@MainActor
final class PhotoPreviewHostingWindow: NSWindow {
    var photoPreview: PhotoPreviewController?
    var onClose: (() -> Void)?

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        photoPreview?.hasItems == true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        photoPreview?.beginControl(panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        photoPreview?.endControl(panel)
    }

    override func close() {
        onClose?()
        photoPreview?.close()
        super.close()
    }
}

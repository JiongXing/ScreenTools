import AppKit

/// 相册传输用到的文件名处理。
enum PhotoNaming {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "dng", "webp", "bmp"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "3gp", "3g2", "avi", "mkv", "webm"]

    static func isImage(_ path: String) -> Bool {
        imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    static func isVideo(_ path: String) -> Bool {
        videoExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    static func isMedia(_ path: String) -> Bool { isImage(path) || isVideo(path) }

    static func transferTimeout(for path: String) -> TimeInterval { isVideo(path) ? 900 : 300 }

    /// 传到手机上的文件名：只保留字母、数字和 ._-，其它字符（空格、引号等）换成下划线
    static func safeName(_ name: String) -> String {
        let mapped = name.unicodeScalars.map { scalar -> Character in
            let ok = CharacterSet.alphanumerics.contains(scalar) || "._-".unicodeScalars.contains(scalar)
            return ok ? Character(scalar) : "_"
        }
        let result = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return result.isEmpty ? "image" : result
    }

    /// 重名时在扩展名前加 _2、_3…，直到 isTaken 返回 false
    static func unique(_ name: String, isTaken: (String) -> Bool) -> String {
        guard isTaken(name) else { return name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base)_\(n)" : "\(base)_\(n).\(ext)"
            if !isTaken(candidate) { return candidate }
            n += 1
        }
    }

    /// 把导出文件的修改时间设成手机上的拍摄/保存时间，方便在 Finder 里按日期排序
    static func stampDate(_ date: Date, on url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    /// 展开用户选择或拖入的文件和文件夹，得到图片和视频（文件夹会递归）。
    static func collectMedia(from urls: [URL]) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                guard let files = fm.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                else { continue }
                for case let file as URL in files where isMedia(file.path) {
                    guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                    result.append(file)
                }
            } else if !url.lastPathComponent.hasPrefix("."), isMedia(url.path) {
                result.append(url)
            }
        }
        return result
    }

    /// 导出和预览共用命名规则，处理不同相簿中的同名文件。
    static func exportJobs(_ items: [PhotoItem], to directory: URL) -> [(item: PhotoItem, destination: URL)] {
        var used = Set<String>()
        return items.map { item in
            let name = unique(item.name) {
                used.contains($0.lowercased()) || FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
            }
            used.insert(name.lowercased())
            return (item, directory.appendingPathComponent(name))
        }
    }
}

/// 手机相册 ↔ 电脑：读取、导入、导出及预览图片和视频。
@MainActor
final class PhotoTransfer: ObservableObject {
    enum Activity: Equatable {
        case listing
        case exporting(done: Int, total: Int)
        case importing(done: Int, total: Int)
        case previewing(done: Int, total: Int)
    }

    /// 一次最多列出的项数（手机上更早的媒体不显示）
    static let listLimit = 500

    private let manager: DeviceManager
    @Published private(set) var items: [PhotoItem] = []
    @Published private(set) var total = 0
    /// 当前列表对应的设备；导出和预览均使用它，保证媒体和设备一致
    @Published private(set) var listedDevice: Device?
    @Published var selection: Set<PhotoItem.ID> = []
    @Published private(set) var activity: Activity?
    /// 操作结果提示（成功/部分失败）
    @Published private(set) var message: String?
    @Published private(set) var error: String?
    /// 最近一次导出所在的文件夹，用于「在 Finder 中显示」
    @Published private(set) var exportedFolder: URL?

    private var task: Task<Void, Never>?
    private var airDrop: NSSharingService?
    let previewController = PhotoPreviewController()

    init(manager: DeviceManager) {
        self.manager = manager
    }

    var isBusy: Bool { activity != nil }

    /// 导出位置：保存位置（默认「下载」）下的「手机相册」文件夹
    static var exportDirectory: URL {
        ImageOutput.saveDirectory.appendingPathComponent("手机相册", isDirectory: true)
    }

    // MARK: - 列表

    func reload() {
        guard !isBusy else { return }
        run(.listing) { [self] in try await loadList() }
    }

    private func loadList() async throws {
        let device = try await manager.target()
        let listing = try await manager.provider(for: device).listPhotos(device, limit: Self.listLimit)
        listedDevice = device
        items = listing.items
        total = listing.total
        selection = []
    }

    // MARK: - 导出（手机 → 电脑）

    func exportSelected() {
        guard !isBusy, let device = listedDevice else { return }
        let chosen = items.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else { return }
        run(.exporting(done: 0, total: chosen.count)) { [self] in
            let dir = Self.exportDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let jobs = PhotoNaming.exportJobs(chosen, to: dir)
            let failures = try await manager.provider(for: device).exportPhotos(device, jobs: jobs) { done in
                self.activity = .exporting(done: done, total: chosen.count)
            }
            exportedFolder = dir
            let ok = chosen.count - failures.count
            message = failures.isEmpty
                ? "已导出 \(ok) 项到「\(dir.deletingLastPathComponent().lastPathComponent)/手机相册」"
                : "已导出 \(ok) 项，\(failures.count) 项失败（\(failures.values.first ?? "")）"
            AppLog.write("exported \(ok)/\(chosen.count) photos from \(device.key) to \(dir.path)")
        }
    }

    // MARK: - 预览（临时下载，不写入导出目录）

    func previewSelected() {
        guard !isBusy, let device = listedDevice else { return }
        let chosen = items.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else { return }
        previewController.close()
        run(.previewing(done: 0, total: chosen.count)) { [self] in
            let session = try await PhotoPreviewSession.prepare(
                chosen, device: device, provider: manager.provider(for: device)
            ) { done in
                self.activity = .previewing(done: done, total: chosen.count)
            }
            try previewController.present(session)
            message = session.failureCount == 0
                ? "已打开 \(session.urls.count) 项预览"
                : "已打开 \(session.urls.count) 项预览，\(session.failureCount) 项下载失败"
        }
    }

    // MARK: - 导入（电脑 → 手机）

    func importFiles(_ urls: [URL]) {
        guard !isBusy else { return }
        let files = PhotoNaming.collectMedia(from: urls)
        guard !files.isEmpty else {
            error = "没有可导入的图片和视频（支持 JPG、HEIC、PNG、MP4、MOV 等）"
            message = nil
            return
        }
        run(.importing(done: 0, total: files.count)) { [self] in
            let device = try await manager.target()
            if device.platform == .ios {
                try sendViaAirDrop(files)
                return
            }
            let failures = try await manager.android.importPhotos(device, files: files) { done in
                self.activity = .importing(done: done, total: files.count)
            }
            let ok = files.count - failures.count
            message = failures.isEmpty
                ? "已传到手机的「Pictures/ScreenTools」，相册里可能要等几秒才会出现（共 \(ok) 项）"
                : "已传 \(ok) 项，\(failures.count) 项失败（\(failures.keys.first ?? "")：\(failures.values.first ?? "")）"
            AppLog.write("imported \(ok)/\(files.count) photos to \(device.key)")
            activity = .listing
            try? await loadList()
        }
    }

    /// iPhone 无法从电脑直接写入「照片」，通过隔空投送交给系统接收媒体。
    private func sendViaAirDrop(_ files: [URL]) throws {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: files) else {
            throw ShotFailure("无法使用隔空投送：请确认这台 Mac 的蓝牙和 Wi‑Fi 已打开")
        }
        airDrop = service
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: files)
        message = "已打开隔空投送：请选择这台 iPhone 并在手机上接受。系统支持的图片和视频会存入「照片」"
    }

    func cancel() { task?.cancel() }

    // MARK: - 内部

    private func run(_ start: Activity, _ work: @escaping @MainActor () async throws -> Void) {
        activity = start
        message = nil
        error = nil
        exportedFolder = nil
        task = Task {
            defer { activity = nil }
            do {
                try await work()
            } catch is CancellationError {
                message = "已取消"
            } catch {
                self.error = error.localizedDescription
                AppLog.write("photo transfer failed: \(error.localizedDescription)")
            }
        }
    }
}

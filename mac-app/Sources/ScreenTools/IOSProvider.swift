import Foundation

/// iPhone / iPad：通过常驻的 Python 辅助进程（pymobiledevice3）列设备和截图。
@MainActor
final class IOSProvider: DeviceProvider {
    let helper = HelperClient()

    func start() { helper.start() }
    func stop() { helper.stop() }

    func readClipboard(_ device: Device) async throws -> String? {
        let reply = await helper.send("clipboard_get", ["udid": device.serial], timeout: 240)
        guard reply["ok"] as? Bool == true else {
            throw ShotFailure(reply["message"] as? String ?? "读取 iPhone 剪贴板失败")
        }
        return reply["text"] as? String
    }

    func writeClipboard(_ device: Device, text: String) async throws {
        guard text.utf8.count <= 1024 * 1024 else {
            throw ShotFailure("文本过长，iPhone 剪贴板单次最多支持 1 MiB UTF-8 文本")
        }
        let reply = await helper.send("clipboard_set", ["udid": device.serial, "text": text], timeout: 240)
        guard reply["ok"] as? Bool == true else {
            throw ShotFailure(reply["message"] as? String ?? "写入 iPhone 剪贴板失败")
        }
    }

    func devices(refresh: Bool) async -> [Device] {
        let reply = await helper.send("list", ["refresh": refresh], timeout: refresh ? 60 : 30)
        guard reply["ok"] as? Bool == true, let list = reply["devices"] as? [[String: Any]] else {
            if let message = reply["message"] as? String {
                AppLog.write("iOS list failed: \(message)")
            }
            return []
        }
        return list.compactMap { item in
            guard let udid = item["udid"] as? String else { return nil }
            var problem = item["message"] as? String
            if problem == nil, item["devMode"] as? Bool == false {
                problem = "未开启开发者模式：设置 → 隐私与安全性 → 开发者模式"
            }
            return Device(
                platform: .ios,
                serial: udid,
                name: item["name"] as? String ?? "iPhone",
                model: item["model"] as? String,
                osVersion: item["version"] as? String,
                connection: item["connection"] as? String == "USB" ? .usb : .wifi,
                problem: problem
            )
        }
    }

    func screenshot(_ device: Device, to url: URL) async throws {
        // 手机重启后首次截图要下载并挂载开发者镜像，给足时间
        let reply = await helper.send("screenshot", ["udid": device.serial, "out": url.path], timeout: 240)
        guard reply["ok"] as? Bool == true else {
            throw ShotFailure(reply["message"] as? String ?? "截图失败")
        }
    }

    // MARK: - 相册（通过 AFC 读取相机胶卷 /DCIM，不需要开发者模式）

    func listPhotos(_ device: Device, limit: Int) async throws -> PhotoListing {
        let reply = await helper.send("photos_list", ["udid": device.serial, "limit": limit], timeout: 120)
        guard reply["ok"] as? Bool == true else {
            throw ShotFailure(reply["message"] as? String ?? "读取相册失败")
        }
        let list = reply["photos"] as? [[String: Any]] ?? []
        let items = list.compactMap { item -> PhotoItem? in
            guard let path = item["path"] as? String else { return nil }
            return PhotoItem(
                id: path,
                size: (item["size"] as? NSNumber)?.int64Value ?? 0,
                date: Date(timeIntervalSince1970: (item["mtime"] as? NSNumber)?.doubleValue ?? 0)
            )
        }
        return PhotoListing(items: items.sorted { $0.date > $1.date }, total: reply["total"] as? Int ?? items.count)
    }

    func exportPhotos(
        _ device: Device,
        jobs: [(item: PhotoItem, destination: URL)],
        onProgress: @MainActor (Int) -> Void
    ) async throws -> [String: String] {
        var failures: [String: String] = [:]
        var done = 0
        // 图片最多八项一批；视频单独请求，超时不会累积到同批其它视频上。
        for batch in Self.transferBatches(jobs) {
            try Task.checkCancellation()
            let items = batch.map { ["path": $0.item.id, "out": $0.destination.path] }
            let reply = await helper.send("photos_pull", ["udid": device.serial, "items": items], timeout: Self.pullTimeout(for: batch))
            guard reply["ok"] as? Bool == true else {
                batch.forEach { try? FileManager.default.removeItem(at: $0.destination) }
                throw ShotFailure(reply["message"] as? String ?? "导出失败")
            }
            let results = reply["results"] as? [[String: Any]] ?? []
            for job in batch {
                let result = results.first { $0["path"] as? String == job.item.id }
                if result?["ok"] as? Bool == true {
                    PhotoNaming.stampDate(job.item.date, on: job.destination)
                } else {
                    failures[job.item.id] = result?["error"] as? String ?? "未知错误"
                    try? FileManager.default.removeItem(at: job.destination)
                }
            }
            done += batch.count
            onProgress(done)
        }
        return failures
    }

    static func transferBatches(
        _ jobs: [(item: PhotoItem, destination: URL)]
    ) -> [[(item: PhotoItem, destination: URL)]] {
        var result: [[(item: PhotoItem, destination: URL)]] = []
        var images: [(item: PhotoItem, destination: URL)] = []
        for job in jobs {
            if job.item.isVideo {
                if !images.isEmpty { result.append(images); images = [] }
                result.append([job])
            } else {
                images.append(job)
                if images.count == 8 { result.append(images); images = [] }
            }
        }
        if !images.isEmpty { result.append(images) }
        return result
    }

    static func pullTimeout(for jobs: [(item: PhotoItem, destination: URL)]) -> TimeInterval {
        (jobs.contains { $0.item.isVideo } ? 900 : 240) + 30
    }
}

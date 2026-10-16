import Foundation

/// iPhone / iPad：通过常驻的 Python 辅助进程（pymobiledevice3）列设备和截图。
@MainActor
final class IOSProvider: DeviceProvider {
    let helper = HelperClient()

    func start() { helper.start() }
    func stop() { helper.stop() }

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
        // 每次让辅助进程拷一小批，避免每张图都重新建立连接，又能及时更新进度
        for batch in jobs.chunked(into: 8) {
            try Task.checkCancellation()
            let items = batch.map { ["path": $0.item.id, "out": $0.destination.path] }
            let reply = await helper.send("photos_pull", ["udid": device.serial, "items": items], timeout: 270)
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
}

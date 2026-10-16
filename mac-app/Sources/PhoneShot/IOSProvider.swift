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
}

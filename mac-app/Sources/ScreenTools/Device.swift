import Foundation

enum Platform: String {
    case ios
    case android
}

struct Device: Equatable {
    enum Connection: String {
        case usb = "USB"
        case wifi = "Wi‑Fi"
    }

    let platform: Platform
    /// iOS 为 UDID，Android 为 adb 序列号
    let serial: String
    var name: String
    var model: String?
    var osVersion: String?
    var connection: Connection
    /// 非 nil 表示设备暂时截不了图，内容是给用户看的原因和解决办法
    var problem: String?

    /// 在 UserDefaults 中记录所选设备用的唯一键
    var key: String { "\(platform.rawValue):\(serial)" }

    var osLabel: String? {
        guard let osVersion, !osVersion.isEmpty else { return nil }
        return platform == .ios ? "iOS \(osVersion)" : "Android \(osVersion)"
    }

    /// 截图文件名前缀，如 iPhone_20261011_110337.jpg
    var filePrefix: String {
        switch platform {
        case .ios: return (model ?? "").hasPrefix("iPad") ? "iPad" : "iPhone"
        case .android: return "Android"
        }
    }

    /// 菜单里第二行显示的详情
    var detail: String {
        [model, osLabel, connection.rawValue].compactMap { $0 }.joined(separator: " · ")
    }
}

/// 截图失败，message 直接展示给用户
struct ShotFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
protocol DeviceProvider: AnyObject {
    /// refresh 为 true 时（打开菜单）重新读取设备状态；false 时（截图前）尽量走缓存、求快
    func devices(refresh: Bool) async -> [Device]
    /// 截图并把 PNG 写到 url；失败抛出 ShotFailure
    func screenshot(_ device: Device, to url: URL) async throws
}

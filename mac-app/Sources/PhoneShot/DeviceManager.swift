import Foundation

/// 汇总 iOS 与 Android 设备，记住用户选择的设备，并决定截图目标。
@MainActor
final class DeviceManager: ObservableObject {
    let ios = IOSProvider()
    let android = AndroidProvider()

    @Published private(set) var devices: [Device] = []
    @Published private(set) var hasLoaded = false
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let selectedKeyName = "selectedDeviceKey"
    private let selectedLabelName = "selectedDeviceName"

    /// nil 表示「自动选择」
    var selectedKey: String? {
        defaults.string(forKey: selectedKeyName)
    }

    /// 所选设备的名字（设备断开时菜单里仍能显示）
    var selectedName: String? {
        defaults.string(forKey: selectedLabelName)
    }

    func select(_ device: Device?) {
        objectWillChange.send()
        defaults.set(device?.key, forKey: selectedKeyName)
        defaults.set(device?.name, forKey: selectedLabelName)
        onChange?()
    }

    func provider(for device: Device) -> DeviceProvider {
        device.platform == .ios ? ios : android
    }

    func refresh(full: Bool) async {
        async let iosDevices = ios.devices(refresh: full)
        async let androidDevices = android.devices(refresh: full)
        devices = await iosDevices + androidDevices
        hasLoaded = true
        onChange?()
    }

    /// 自动选择时的目标：可用的优先，其次数据线优先
    var autoChoice: Device? {
        devices.enumerated().min { a, b in
            let ra = (a.element.problem == nil ? 0 : 2) + (a.element.connection == .usb ? 0 : 1)
            let rb = (b.element.problem == nil ? 0 : 2) + (b.element.connection == .usb ? 0 : 1)
            return (ra, a.offset) < (rb, b.offset)
        }?.element
    }

    /// 截图前调用：快速刷新设备列表并返回目标设备
    func target() async throws -> Device {
        await refresh(full: false)
        if let key = selectedKey {
            if let device = devices.first(where: { $0.key == key }) {
                return device
            }
            let name = selectedName ?? "所选设备"
            throw ShotFailure("「\(name)」未连接：请重新连接，或在菜单中改为「自动选择」")
        }
        guard let device = autoChoice else {
            throw ShotFailure(noDeviceMessage)
        }
        return device
    }

    var noDeviceMessage: String {
        var message = "没有检测到手机：iPhone 请用数据线连接并信任此电脑；Android 请打开 USB 调试后连接"
        if !android.isAvailable {
            message += "（未找到 adb，暂不支持 Android）"
        }
        return message
    }
}

import AppKit
import Carbon
import Foundation

extension Notification.Name {
    static let showSettings = Notification.Name("ScreenToolsShowSettings")
}

/// 一个全局快捷键：Carbon 键码 + Carbon 修饰键 + 用于显示的按键名。
struct HotKeySpec: Equatable, Codable {
    var keyCode: Int
    var modifiers: Int
    var label: String

    /// 正在录入快捷键时，暂停响应已有快捷键
    nonisolated(unsafe) static var isRecording = false

    init(keyCode: Int, modifiers: Int, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    init(event: NSEvent) {
        var mods = 0
        let flags = event.modifierFlags
        if flags.contains(.command) { mods |= cmdKey }
        if flags.contains(.shift) { mods |= shiftKey }
        if flags.contains(.option) { mods |= optionKey }
        if flags.contains(.control) { mods |= controlKey }
        let label = (event.charactersIgnoringModifiers ?? "").uppercased()
        self.init(keyCode: Int(event.keyCode), modifiers: mods, label: label.isEmpty ? "?" : label)
    }

    func matches(_ event: NSEvent) -> Bool {
        let other = HotKeySpec(event: event)
        return other.keyCode == keyCode && other.modifiers == modifiers
    }

    var display: String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + label
    }
}

/// 用户偏好，统一存放在 UserDefaults。
enum Settings {
    private static let defaults = UserDefaults.standard

    static let defaultJPEGQuality = 0.8

    static var jpegQuality: Double {
        get { defaults.object(forKey: "jpegQuality") as? Double ?? defaultJPEGQuality }
        set { defaults.set(min(1, max(0.1, newValue)), forKey: "jpegQuality") }
    }

    /// 自定义保存目录；nil 表示「下载」
    static var saveDirectoryPath: String? {
        get { defaults.string(forKey: "saveDirectory") }
        set { defaults.set(newValue, forKey: "saveDirectory") }
    }

    static var allowURLScheme: Bool {
        get { defaults.object(forKey: "allowURLScheme") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "allowURLScheme") }
    }

    /// 默认不启用任何全局快捷键；nil 表示未设置
    static func hotKey(_ name: String) -> HotKeySpec? {
        guard let data = defaults.data(forKey: "hotkey.\(name)") else { return nil }
        return try? JSONDecoder().decode(HotKeySpec.self, from: data)
    }

    static func setHotKey(_ name: String, _ spec: HotKeySpec?) {
        if let spec {
            defaults.set(try? JSONEncoder().encode(spec), forKey: "hotkey.\(name)")
        } else {
            defaults.removeObject(forKey: "hotkey.\(name)")
        }
    }

    static var jpegHotKey: HotKeySpec? {
        get { hotKey("jpeg") }
        set { setHotKey("jpeg", newValue) }
    }

    static var pngHotKey: HotKeySpec? {
        get { hotKey("png") }
        set { setHotKey("png", newValue) }
    }

    /// 截图历史（文件路径，新的在前）
    static var historyPaths: [String] {
        get { defaults.stringArray(forKey: "history") ?? [] }
        set { defaults.set(newValue, forKey: "history") }
    }
}

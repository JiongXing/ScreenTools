import AppKit
import Carbon

private let shortcutSignature: OSType = 0x5344494D

/// 盖在一块屏幕上的黑色遮罩：鼠标可穿透，不抢焦点，覆盖全屏应用和所有桌面空间。
final class DimWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen, opacity: Double) {
        super.init(contentRect: screen.frame, styleMask: .borderless,
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        backgroundColor = .black
        alphaValue = opacity
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
}

/// 屏幕压暗：用黑色遮罩临时压暗所有活动屏幕，不改硬件背光。
/// 全局快捷键 ⌃⌥⌘B 切换、⌃⌥⌘R 始终恢复（Carbon 热键，不需要任何系统权限）。
/// 退出、睡眠、唤醒都会移除遮罩。
@MainActor
final class ScreenDimmer: ObservableObject {
    static let strengths: [(title: String, value: Double)] = [
        ("柔和 · 85%", 0.85), ("很暗 · 95%", 0.95), ("最低 · 98%", 0.98),
    ]
    private static let strengthKey = "dimOpacity"

    @Published private(set) var isDimmed = false
    @Published private(set) var screenCount = NSScreen.screens.count
    @Published private(set) var shortcutsAvailable = true
    @Published private(set) var opacity: Double = ScreenDimmer.savedOpacity

    private var overlays: [DimWindow] = []
    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?

    private static var savedOpacity: Double {
        let saved = UserDefaults.standard.double(forKey: strengthKey)
        return strengths.contains { $0.value == saved } ? saved : 0.98
    }

    func start() {
        registerShortcuts()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restore() }
            }
        }
    }

    func stop() {
        restore()
        unregisterShortcuts()
    }

    func toggle() {
        if isDimmed { restore(); return }
        guard !NSScreen.screens.isEmpty else { return }
        isDimmed = true
        rebuildOverlays()
    }

    func restore() {
        overlays.forEach { $0.close() }
        overlays.removeAll()
        isDimmed = false
    }

    func setOpacity(_ value: Double) {
        guard Self.strengths.contains(where: { $0.value == value }) else { return }
        UserDefaults.standard.set(value, forKey: Self.strengthKey)
        opacity = value
        overlays.forEach { $0.alphaValue = value }
    }

    private func rebuildOverlays() {
        let previous = overlays
        overlays = NSScreen.screens.map { DimWindow(screen: $0, opacity: opacity) }
        overlays.forEach { $0.orderFrontRegardless() }
        previous.forEach { $0.close() }
    }

    private func screensChanged() {
        screenCount = NSScreen.screens.count
        if isDimmed { rebuildOverlays() }
    }

    /// `--self-check`：检查活动屏幕、遮罩窗口创建与快捷键注册，不显示遮罩。返回是否通过。
    func selfCheck() -> Bool {
        let screens = NSScreen.screens
        let windows = screens.map { DimWindow(screen: $0, opacity: opacity) }
        let valid = !screens.isEmpty && shortcutsAvailable && windows.allSatisfy {
            $0.ignoresMouseEvents && !$0.canBecomeKey && $0.alphaValue > 0
        }
        print("screens=\(screens.count), shortcuts=\(shortcutsAvailable), windows=\(windows.count), opacity=\(opacity), passed=\(valid)")
        for screen in screens { print("\(screen.localizedName): \(screen.frame)") }
        windows.forEach { $0.close() }
        return valid
    }

    // MARK: - 全局快捷键

    private func registerShortcuts() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, context in
            guard let event = event, let context = context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == shortcutSignature else { return OSStatus(eventNotHandledErr) }
            let dimmer = Unmanaged<ScreenDimmer>.fromOpaque(context).takeUnretainedValue()
            // Carbon 热键回调运行在主线程
            MainActor.assumeIsolated {
                if id.id == 1 { dimmer.toggle() }
                if id.id == 2 { dimmer.restore() }
            }
            return noErr
        }
        let installed = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &type,
            Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard installed == noErr else { shortcutsAvailable = false; return }
        for (id, key) in [(UInt32(1), UInt32(kVK_ANSI_B)), (UInt32(2), UInt32(kVK_ANSI_R))] {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(key, UInt32(controlKey | optionKey | cmdKey),
                EventHotKeyID(signature: shortcutSignature, id: id), GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref = ref { hotKeys.append(ref) }
            else { shortcutsAvailable = false }
        }
    }

    private func unregisterShortcuts() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let eventHandler = eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }
}

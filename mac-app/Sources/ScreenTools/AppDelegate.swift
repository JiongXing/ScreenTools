import AppKit
import SwiftUI

/// Dock 应用：没有菜单栏图标。关闭窗口不会退出进程，点 Dock 图标可重新打开窗口。
/// 截图快捷键只在本 App 处于前台时有效（本地事件监听，不需要任何系统权限）；
/// 屏幕压暗的 ⌃⌥⌘B / ⌃⌥⌘R 是全局快捷键。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let manager = DeviceManager()
    private lazy var shots = ShotController(manager: manager)
    private lazy var photos = PhotoTransfer(manager: manager)
    private lazy var clipboard = ClipboardController(manager: manager)
    private let dimmer = ScreenDimmer()

    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var keyMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // screentools://capture?format=png、screentools://dim 等 —— 供快捷指令、Raycast 等外部工具触发
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        dimmer.start()
        if CommandLine.arguments.contains("--self-check") {
            let passed = dimmer.selfCheck()
            dimmer.stop()
            exit(passed ? 0 : 1)
        }
        PhotoPreviewSession.cleanupStaleSessions()
        NSApp.mainMenu = makeMainMenu()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) ?? event }
        }
        NotificationCenter.default.addObserver(forName: .showSettings, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showSettings() }
        }
        manager.ios.start()
        showMainWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        photos.cancel()
        photos.previewController.close()
        dimmer.stop()
        manager.ios.stop()
        manager.android.stopClipboard()
    }

    /// 关掉窗口后进程继续运行
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// 点 Dock 图标：窗口被关了就重新打开
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard mainWindow?.isVisible == true else { return }
        Task { await manager.refresh(full: true) }
    }

    // MARK: - 键盘

    /// 返回 nil 表示事件已处理
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard !HotKeySpec.isRecording else { return event }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command {
            switch event.charactersIgnoringModifiers {
            case "w": NSApp.keyWindow?.close(); return nil
            case "q": NSApp.terminate(nil); return nil
            case ",": showSettings(); return nil
            default: break
            }
        }
        if let spec = Settings.jpegHotKey, spec.matches(event) { shots.take(.jpeg); return nil }
        if let spec = Settings.pngHotKey, spec.matches(event) { shots.take(.png); return nil }
        return event
    }

    // MARK: - 菜单

    /// 手动启动的 App 没有默认主菜单；文本框的 ⌘A/⌘C/⌘V/⌘X/⌘Z 靠「编辑」菜单的快捷键分发到第一响应者。
    /// ⌘W/⌘Q/⌘, 由 handleKey 先处理，这里的同名项只用于显示。
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 屏幕工具箱", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 屏幕工具箱", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "编辑", action: nil, keyEquivalent: "").submenu = edit

        let window = NSMenu(title: "窗口")
        window.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: "窗口", action: nil, keyEquivalent: "").submenu = window
        NSApp.windowsMenu = window
        return main
    }

    @objc private func openSettings() { showSettings() }

    // MARK: - 窗口

    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "屏幕工具箱 设置"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        } else {
            // 重新创建内容以读取最新偏好
            settingsWindow?.contentViewController = NSHostingController(rootView: SettingsView())
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showMainWindow() {
        if mainWindow == nil {
            let host = NSHostingController(rootView: MainView(manager: manager, shots: shots, transfer: photos, dimmer: dimmer, clipboard: clipboard))
            host.sizingOptions = []
            let window = PhotoPreviewHostingWindow(contentViewController: host)
            window.photoPreview = photos.previewController
            window.onClose = { [weak self] in self?.photos.cancel() }
            window.title = "屏幕工具箱"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 720 * UIScale.factor, height: 480 * UIScale.factor))
            window.contentMinSize = NSSize(width: 640 * UIScale.factor, height: 440 * UIScale.factor)
            window.isReleasedWhenClosed = false
            window.center()
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
        Task { await manager.refresh(full: true) }
    }

    // MARK: - 外部触发

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard Settings.allowURLScheme,
              let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URLComponents(string: text) else { return }
        switch url.host {
        case "show": showMainWindow(); return
        case "dim": dimmer.toggle(); return
        case "restore": dimmer.restore(); return
        default: break
        }
        guard url.host == "capture" else { return }
        let format = url.queryItems?.first { $0.name == "format" }?.value
        shots.take(format == "png" ? .png : .jpeg)
    }
}

import Carbon
import AppKit
import ServiceManagement
import SwiftUI

/// 点击后按下新的组合键即可录入，Esc 取消。用本地事件监听捕获按键，不依赖 AppKit 视图的点击测试，放大后也正常。
struct HotKeyRecorder: View {
    @Binding var spec: HotKeySpec?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(recording ? "按下新的组合键…" : (spec?.display ?? "未设置")) { toggle() }
                .buttonStyle(UIButtonStyle())
                .frame(minWidth: S(120))
            if spec != nil && !recording {
                Button { spec = nil } label: { Image(systemName: "xmark.circle.fill").font(.ui(15)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("清除快捷键")
            }
        }
        .onDisappear { stop() }
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        recording = true
        HotKeySpec.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stop()
                return nil
            }
            let candidate = HotKeySpec(event: event)
            let mods = candidate.modifiers
            // 至少要有 ⌘ / ⌃ / ⌥ 之一，否则会吞掉普通输入
            guard mods & (cmdKey | controlKey | optionKey) != 0 else { NSSound.beep(); return nil }
            spec = candidate
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        HotKeySpec.isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

struct SettingsView: View {
    @State private var jpegKey = Settings.jpegHotKey
    @State private var pngKey = Settings.pngHotKey
    @State private var quality = Settings.jpegQuality
    @State private var folder = ImageOutput.saveDirectory.path
    @State private var allowURL = Settings.allowURLScheme
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: S(18)) {
            section("快捷键") {
                row("截图（JPEG）") { HotKeyRecorder(spec: $jpegKey) }
                row("截图（PNG）") { HotKeyRecorder(spec: $pngKey) }
                Text("默认不设置快捷键。快捷键仅在 PhoneShot 处于前台时有效：点击按钮后按下组合键（需含 ⌘、⌃ 或 ⌥）。⌘W 关闭窗口（不退出），⌘Q 退出。")
                    .font(.ui(11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            section("保存") {
                row("保存位置") {
                    HStack(spacing: S(8)) {
                        Text(folder).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("选择…") { chooseFolder() }.buttonStyle(UIButtonStyle())
                        if Settings.saveDirectoryPath != nil {
                            Button("恢复为下载") {
                                Settings.saveDirectoryPath = nil
                                folder = ImageOutput.saveDirectory.path
                            }
                            .buttonStyle(UIButtonStyle())
                        }
                    }
                }
                row("JPEG 质量 \(Int(quality * 100))%") {
                    UISlider(value: $quality, range: 0.3...1, step: 0.05).frame(width: S(200))
                }
            }
            section("通用") {
                Toggle("开机自动启动", isOn: $launchAtLogin).toggleStyle(UICheckToggleStyle())
                Toggle("允许外部工具通过 phoneshot:// 触发截图", isOn: $allowURL).toggleStyle(UICheckToggleStyle())
            }
        }
        .font(.ui(13))
        .padding(S(20))
        .frame(width: S(520), alignment: .leading)
        .onChange(of: jpegKey) { Settings.jpegHotKey = $0 }
        .onChange(of: pngKey) { Settings.pngHotKey = $0 }
        .onChange(of: quality) { Settings.jpegQuality = $0 }
        .onChange(of: allowURL) { Settings.allowURLScheme = $0 }
        .onChange(of: launchAtLogin) { enabled in
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
                Notifier.warning(title: "设置开机启动失败", body: error.localizedDescription)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: S(10)) {
            Text(title).font(.ui(15, .semibold))
            content()
        }
    }

    private func row<Control: View>(_ label: String, @ViewBuilder _ control: () -> Control) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: S(12))
            control()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            Settings.saveDirectoryPath = url.path
            folder = url.path
        }
    }
}

import SwiftUI

/// 「屏幕压暗」页：原菜单栏里的压暗/恢复、压暗程度、屏幕数量和说明都放在这里。
struct DimmerView: View {
    @ObservedObject var dimmer: ScreenDimmer

    var body: some View {
        VStack(alignment: .leading, spacing: S(18)) {
            VStack(alignment: .leading, spacing: S(4)) {
                Text(dimmer.isDimmed ? "屏幕已压暗" : "屏幕正常显示").font(.ui(16, .semibold))
                Text("当前连接 \(dimmer.screenCount) 块屏幕").font(.ui(12)).foregroundStyle(.secondary)
            }
            HStack(spacing: S(8)) {
                Button { dimmer.toggle() } label: {
                    Label(dimmer.isDimmed ? "恢复所有屏幕" : "压暗所有屏幕",
                          systemImage: dimmer.isDimmed ? "sun.max" : "moon")
                }
                .buttonStyle(UIButtonStyle(prominent: !dimmer.isDimmed))
                Button { dimmer.restore() } label: { Label("始终恢复", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(UIButtonStyle())
                    .disabled(!dimmer.isDimmed)
            }
            VStack(alignment: .leading, spacing: S(8)) {
                Text("压暗程度").font(.ui(12)).foregroundStyle(.secondary)
                HStack(spacing: S(8)) {
                    ForEach(ScreenDimmer.strengths, id: \.value) { item in
                        let on = abs(item.value - dimmer.opacity) < 0.001
                        Button { dimmer.setOpacity(item.value) } label: {
                            Label(item.title, systemImage: on ? "checkmark.circle.fill" : "circle")
                        }
                        .buttonStyle(UIButtonStyle(prominent: on))
                    }
                }
            }
            VStack(alignment: .leading, spacing: S(4)) {
                Text("全局快捷键（在任何位置都有效）").font(.ui(12)).foregroundStyle(.secondary)
                Text("⌃⌥⌘B　压暗 / 恢复").font(.ui(13))
                Text("⌃⌥⌘R　始终恢复").font(.ui(13))
                if !dimmer.shortcutsAvailable {
                    Label("快捷键注册失败，可能被其它应用占用。可在此页面操作，或关闭占用快捷键的应用后重启。",
                          systemImage: "exclamationmark.triangle")
                        .font(.ui(12)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("用黑色半透明遮罩压暗所有正在使用的屏幕，鼠标仍可正常操作；不改变显示器背光，不等同于关闭屏幕或省电。退出应用、电脑睡眠或唤醒都会自动恢复。无需辅助功能或屏幕录制权限。")
                .font(.ui(11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(S(20))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

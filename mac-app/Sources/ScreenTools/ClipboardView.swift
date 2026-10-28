import SwiftUI

struct ClipboardView: View {
    @ObservedObject var manager: DeviceManager
    @ObservedObject var clipboard: ClipboardController

    var body: some View {
        VStack(alignment: .leading, spacing: S(12)) {
            Text("剪贴板").font(.ui(16, .semibold))
            Text("电脑：这台 Mac  ·  手机：\(targetName)")
                .font(.ui(12)).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: S(8)) { computerButtons; phoneButtons }
                VStack(alignment: .leading, spacing: S(8)) {
                    HStack(spacing: S(8)) { computerButtons }
                    HStack(spacing: S(8)) { phoneButtons }
                }
            }
            .buttonStyle(UIButtonStyle())
            .disabled(clipboard.isBusy)
            TextEditor(text: $clipboard.text)
                .font(.ui(13))
                .padding(S(6))
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: S(8)))
                .overlay(RoundedRectangle(cornerRadius: S(8)).strokeBorder(Color.secondary.opacity(0.35)))
                .disabled(clipboard.isBusy)
                .accessibilityLabel("剪贴板文本")
            if clipboard.isBusy { ProgressView().controlSize(.small) }
            if let error = clipboard.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.ui(12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else if let status = clipboard.status {
                Text(status).font(.ui(12)).foregroundStyle(.secondary)
            }
            Text("读取到这里查看和编辑，再点击写入。仅支持文本和链接；写入会替换目标剪贴板，不会自动粘贴。")
                .font(.ui(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(S(16))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var targetName: String {
        if let key = manager.selectedKey {
            return manager.devices.first { $0.key == key }?.name ?? "所选手机未连接"
        }
        return manager.autoChoice?.name ?? "未连接"
    }

    @ViewBuilder private var computerButtons: some View {
        Button("读取电脑") { clipboard.readComputer() }
        Button("写入电脑") { clipboard.writeComputer() }
    }

    @ViewBuilder private var phoneButtons: some View {
        Button("读取手机") { Task { await clipboard.readPhone() } }
        Button("写入手机") { Task { await clipboard.writePhone() } }
    }
}

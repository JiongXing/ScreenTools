import AppKit
import SwiftUI

/// 主窗口：左侧设备列表，右侧最近截图预览、截图/复制/定位按钮和历史。
/// 所有尺寸都经过 S()/.ui() 逐个放大。
struct MainView: View {
    @ObservedObject var manager: DeviceManager
    @ObservedObject var shots: ShotController
    @State private var selected: URL?
    @State private var openAfter = ShotController.openAfterCapture

    private var preview: URL? { selected ?? shots.history.first }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                detail
            }
            Divider()
            statusBar
        }
        .onChange(of: shots.history) { _ in selected = nil }
    }

    private var hotKeyHint: String {
        let parts = [Settings.jpegHotKey.map { "\($0.display)（JPEG）" }, Settings.pngHotKey.map { "\($0.display)（PNG）" }]
            .compactMap { $0 }
        return parts.isEmpty ? "可在设置里添加截图快捷键" : "在任何位置按 " + parts.joined(separator: " 或 ")
    }

    // MARK: - 设备

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: S(8)) {
            Text("设备").font(.ui(12)).foregroundStyle(.secondary)
            if manager.devices.isEmpty {
                Text(manager.hasLoaded ? "未检测到设备" : "正在检测…")
                    .font(.ui(13)).foregroundStyle(.secondary).padding(.vertical, S(6))
            }
            ForEach(manager.devices, id: \.key) { device in
                deviceRow(device)
            }
            Spacer()
            autoRow
            Button {
                Task { await manager.refresh(full: true) }
            } label: {
                Label("刷新设备列表", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(UIButtonStyle())
        }
        .padding(S(12))
        .frame(width: S(220))
        .background(Color.secondary.opacity(0.08))
    }

    private func deviceRow(_ device: Device) -> some View {
        let isSelected = manager.selectedKey == device.key
        return Button { manager.select(device) } label: {
            HStack(alignment: .top, spacing: S(8)) {
                Image(systemName: device.platform == .ios ? "iphone" : "smartphone")
                    .font(.ui(16))
                    .frame(width: S(20))
                VStack(alignment: .leading, spacing: S(2)) {
                    Text(device.name).font(.ui(13, isSelected ? .semibold : .regular))
                    Text(device.problem ?? device.detail)
                        .font(.ui(11))
                        .foregroundStyle(device.problem == nil ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(S(8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: S(8)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var autoRow: some View {
        let isAuto = manager.selectedKey == nil
        return Button { manager.select(nil) } label: {
            HStack(spacing: S(8)) {
                Image(systemName: isAuto ? "checkmark.circle.fill" : "circle")
                    .font(.ui(16))
                    .frame(width: S(20))
                VStack(alignment: .leading, spacing: S(2)) {
                    Text("自动选择").font(.ui(13))
                    Text(manager.autoChoice.map { "当前：\($0.name)" } ?? "未检测到设备")
                        .font(.ui(11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(S(8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: S(8))
                .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 预览与操作

    private var detail: some View {
        HStack(alignment: .top, spacing: S(20)) {
            previewPane
            VStack(alignment: .leading, spacing: S(14)) {
                VStack(alignment: .leading, spacing: S(2)) {
                    Text(shots.isBusy ? "正在截图…" : "随时可以截图").font(.ui(16, .semibold))
                    Text(hotKeyHint).font(.ui(12)).foregroundStyle(.secondary)
                }
                if let error = shots.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.ui(12)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: S(8)) {
                    Button { shots.take(.jpeg) } label: { Label("截图（JPEG）", systemImage: "camera") }
                        .buttonStyle(UIButtonStyle())
                    Button { shots.take(.png) } label: { Label("截图（PNG）", systemImage: "photo") }
                        .buttonStyle(UIButtonStyle())
                }
                .disabled(shots.isBusy)
                HStack(spacing: S(8)) {
                    Button { copy() } label: { Label("复制", systemImage: "doc.on.doc") }
                    Button { reveal() } label: { Label("显示", systemImage: "folder") }
                    Button { open() } label: { Label("打开", systemImage: "eye") }
                }
                .buttonStyle(UIButtonStyle())
                .disabled(preview == nil)
                if !shots.history.isEmpty {
                    Text("最近").font(.ui(12)).foregroundStyle(.secondary).padding(.top, S(4))
                    historyStrip
                }
                Spacer(minLength: 0)
            }
        }
        .padding(S(16))
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var previewPane: some View {
        ZStack {
            RoundedRectangle(cornerRadius: S(24)).fill(Color.secondary.opacity(0.12))
            if let url = preview, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: S(16))).padding(S(6))
            } else {
                Text("截图后在这里预览").font(.ui(12)).foregroundStyle(.secondary)
            }
            if shots.isBusy { ProgressView() }
        }
        .frame(width: S(170), height: S(340))
        .overlay(RoundedRectangle(cornerRadius: S(24)).strokeBorder(Color.primary.opacity(0.7), lineWidth: S(5)))
    }

    private var historyStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: S(6)) {
                ForEach(shots.history, id: \.self) { url in
                    Button { selected = url } label: {
                        Group {
                            if let image = NSImage(contentsOf: url) {
                                Image(nsImage: image).resizable().scaledToFill()
                            } else {
                                Color.gray.opacity(0.2)
                            }
                        }
                        .frame(width: S(44), height: S(64))
                        .clipShape(RoundedRectangle(cornerRadius: S(6)))
                        .overlay(RoundedRectangle(cornerRadius: S(6))
                            .strokeBorder(url == preview ? Color.accentColor : Color.secondary.opacity(0.3),
                                          lineWidth: url == preview ? 2 : 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: S(68))
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack(spacing: S(14)) {
            Label("保存到「\(ImageOutput.saveDirectory.lastPathComponent)」", systemImage: "arrow.down.circle")
            Spacer()
            Toggle("截图后用预览打开", isOn: $openAfter)
                .toggleStyle(UICheckToggleStyle())
                .onChange(of: openAfter) { ShotController.openAfterCapture = $0 }
            Button { NotificationCenter.default.post(name: .showSettings, object: nil) } label: {
                Image(systemName: "gearshape").font(.ui(15))
            }
            .buttonStyle(.plain)
            .help("设置")
        }
        .font(.ui(12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, S(14))
        .padding(.vertical, S(8))
    }

    // MARK: - 动作

    private func copy() {
        guard let url = preview, let data = try? Data(contentsOf: url) else { return }
        ImageOutput.copyToPasteboard(data, format: url.pathExtension == "png" ? .png : .jpeg)
    }

    private func reveal() {
        if let url = preview { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    private func open() {
        if let url = preview { NSWorkspace.shared.open(url) }
    }
}

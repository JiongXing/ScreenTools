import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 「手机相册」页：显示、导入、导出及预览手机上的图片和视频。
struct PhotosView: View {
    @ObservedObject var manager: DeviceManager
    @ObservedObject var transfer: PhotoTransfer
    @State private var dropTargeted = false

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: S(12)) {
            header
            actions
            statusLines
            list
        }
        .padding(S(16))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: S(12))
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .background(Color.accentColor.opacity(0.08))
                    .overlay(Text("松开鼠标，把图片和视频传到手机").font(.ui(15, .semibold)).foregroundStyle(Color.accentColor))
                    .padding(S(8))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            Self.fileURLs(from: providers) { transfer.importFiles($0) }
            return true
        }
        .onAppear {
            // 从别的标签切回来时，如果所选设备变了，列表就是旧的
            if transfer.listedDevice == nil || transfer.listedDevice?.key != (manager.selectedKey ?? manager.autoChoice?.key) {
                transfer.reload()
            }
        }
        .onChange(of: manager.selectedKey) { _ in transfer.reload() }
    }

    // MARK: - 部件

    private var header: some View {
        VStack(alignment: .leading, spacing: S(2)) {
            Text("手机相册").font(.ui(16, .semibold))
            Text(subtitle).font(.ui(12)).foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        guard let device = transfer.listedDevice else { return "读取中或未连接设备" }
        var text = device.name
        if transfer.total > transfer.items.count {
            text += " · 共 \(transfer.total) 项，显示最新 \(transfer.items.count) 项"
        } else {
            text += " · 共 \(transfer.total) 项"
        }
        return text
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: S(8)) { primaryActions; secondaryActions }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: S(8)) {
                HStack(spacing: S(8)) { primaryActions }
                HStack(spacing: S(8)) { secondaryActions }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var primaryActions: some View {
        Button { pickFiles() } label: { Label("导入到手机…", systemImage: "square.and.arrow.down") }
            .buttonStyle(UIButtonStyle(prominent: true))
            .disabled(transfer.isBusy)
        Button { transfer.exportSelected() } label: {
            Label(transfer.selection.isEmpty ? "导出所选" : "导出所选（\(transfer.selection.count)）",
                  systemImage: "square.and.arrow.up")
        }
        .buttonStyle(UIButtonStyle())
        .disabled(transfer.isBusy || transfer.selection.isEmpty)
    }

    @ViewBuilder
    private var secondaryActions: some View {
        Button { transfer.previewSelected() } label: { Label("预览", systemImage: "eye") }
            .buttonStyle(UIButtonStyle())
            .disabled(transfer.isBusy || transfer.selection.isEmpty)
        Button { transfer.reload() } label: { Label("刷新", systemImage: "arrow.clockwise") }
            .buttonStyle(UIButtonStyle())
            .disabled(transfer.isBusy)
        if transfer.isBusy, transfer.activity != .listing {
            Button { transfer.cancel() } label: { Label("取消", systemImage: "xmark") }
                .buttonStyle(UIButtonStyle())
        }
    }

    @ViewBuilder
    private var statusLines: some View {
        if let activity = transfer.activity {
            HStack(spacing: S(8)) {
                ProgressView().controlSize(.small)
                Text(activityText(activity)).font(.ui(12)).foregroundStyle(.secondary)
            }
        }
        if let error = transfer.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.ui(12)).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let message = transfer.message {
            HStack(spacing: S(8)) {
                Label(message, systemImage: "checkmark.circle")
                    .font(.ui(12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let folder = transfer.exportedFolder {
                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                        .buttonStyle(.link).font(.ui(12))
                }
            }
        }
    }

    private func activityText(_ activity: PhotoTransfer.Activity) -> String {
        switch activity {
        case .listing: return "正在读取相册…"
        case let .exporting(done, total): return "正在导出 \(done)/\(total)…"
        case let .importing(done, total): return "正在传到手机 \(done)/\(total)…"
        case let .previewing(done, total): return "正在准备预览 \(done)/\(total)…（视频较大时请稍候）"
        }
    }

    private var list: some View {
        Group {
            if transfer.items.isEmpty {
                VStack(spacing: S(6)) {
                    Spacer()
                    Image(systemName: "photo.on.rectangle").font(.ui(28)).foregroundStyle(.secondary)
                    Text(transfer.isBusy ? "" : "手机里没有读到图片和视频").font(.ui(13)).foregroundStyle(.secondary)
                    Text("把电脑上的图片和视频拖到这里，就能传进手机").font(.ui(12)).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(transfer.items, selection: $transfer.selection) { item in
                    HStack {
                        Image(systemName: item.isVideo ? "film" : "photo").font(.ui(13)).foregroundStyle(.secondary)
                        Text(item.name).font(.ui(13))
                        Spacer()
                        Text(Self.sizeText(item.size)).font(.ui(12)).foregroundStyle(.secondary)
                        Text(item.date.timeIntervalSince1970 > 0 ? Self.dateFormat.string(from: item.date) : "")
                            .font(.ui(12)).foregroundStyle(.secondary)
                            .frame(width: S(120), alignment: .trailing)
                    }
                    .padding(.vertical, S(2))
                }
                .listStyle(.inset)
            }
        }
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: S(8)))
        .frame(maxHeight: .infinity)
    }

    // MARK: - 动作

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.title = "选择要传到手机的图片和视频"
        panel.prompt = "传到手机"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .movie] + PhotoNaming.videoExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        transfer.importFiles(panel.urls)
    }

    private static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// 取出拖入的文件地址（回调在主线程）
    private static func fileURLs(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let lock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let result = urls
            MainActor.assumeIsolated { completion(result) }
        }
    }
}

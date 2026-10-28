import CryptoKit
import XCTest
@testable import ScreenTools

/// 显式设置环境变量才访问真机。Android 会导入指定的测试素材，测试后由验收者清理。
@MainActor
final class LiveMediaTests: XCTestCase {
    func testAndroidMediaRoundTrip() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let serial = env["SCREENTOOLS_LIVE_ANDROID"],
              let fixturePath = env["SCREENTOOLS_LIVE_MEDIA"] else {
            throw XCTSkip("设置 SCREENTOOLS_LIVE_ANDROID 与 SCREENTOOLS_LIVE_MEDIA 才运行真机导入/导出")
        }
        let provider = AndroidProvider()
        let devices = await provider.devices(refresh: true)
        let device = try XCTUnwrap(devices.first { $0.serial == serial })
        let files = PhotoNaming.collectMedia(from: [URL(fileURLWithPath: fixturePath)])
        XCTAssertTrue(files.contains { PhotoNaming.isVideo($0.path) })
        XCTAssertTrue(files.contains { PhotoNaming.isImage($0.path) })
        let failures = try await provider.importPhotos(device, files: files) { _ in }
        XCTAssertTrue(failures.isEmpty, "\(failures)")
        let listing = try await provider.listPhotos(device, limit: 500)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("live-android-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: out) }
        for file in files {
            let remote = "\(AndroidProvider.importFolder)/\(PhotoNaming.safeName(file.lastPathComponent))"
            let item = try XCTUnwrap(listing.items.first { $0.id == remote })
            let destination = out.appendingPathComponent(file.lastPathComponent)
            let exportFailures = try await provider.exportPhotos(device, jobs: [(item, destination)]) { _ in }
            XCTAssertTrue(exportFailures.isEmpty)
            let original = try Data(contentsOf: file)
            let downloaded = try Data(contentsOf: destination)
            XCTAssertEqual(Int64(original.count), item.size)
            XCTAssertEqual(SHA256.hash(data: original), SHA256.hash(data: downloaded))
        }
    }

    func testIOSLocalPhotoAndVideoExports() async throws {
        guard let serial = ProcessInfo.processInfo.environment["SCREENTOOLS_LIVE_IOS"] else {
            throw XCTSkip("设置 SCREENTOOLS_LIVE_IOS 才读取真机相册并导出图片和视频")
        }
        let provider = IOSProvider()
        defer { provider.stop() }
        let devices = await provider.devices(refresh: true)
        let device = try XCTUnwrap(devices.first { $0.serial == serial })
        let listing = try await provider.listPhotos(device, limit: 500)
        let video = try XCTUnwrap(listing.items.filter(\.isVideo).min { $0.size < $1.size })
        let image = try XCTUnwrap(listing.items.first { !$0.isVideo })
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("live-ios-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: out) }
        let first = PhotoNaming.exportJobs([video, image], to: out)
        let failures = try await provider.exportPhotos(device, jobs: first) { _ in }
        XCTAssertTrue(failures.isEmpty)
        // 同一原件重复导出应当字节一致，且大小与手机列表一致。
        let second = PhotoNaming.exportJobs([video, image], to: out)
        let repeatedFailures = try await provider.exportPhotos(device, jobs: second) { _ in }
        XCTAssertTrue(repeatedFailures.isEmpty)
        for (a, b) in zip(first, second) {
            let data = try Data(contentsOf: a.destination)
            XCTAssertEqual(Int64(data.count), a.item.size)
            XCTAssertEqual(SHA256.hash(data: data), SHA256.hash(data: try Data(contentsOf: b.destination)))
        }
    }
}

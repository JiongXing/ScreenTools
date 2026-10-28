import XCTest
@testable import ScreenTools

@MainActor
private final class PreviewProvider: DeviceProvider {
    func readClipboard(_ device: Device) async throws -> String? { nil }
    func writeClipboard(_ device: Device, text: String) async throws { }
    var failures: Set<String> = []
    var omitFiles = false
    var disconnect = false
    var cancelAfterLastFile = false
    var receivedDevice: Device?
    var receivedItems: [PhotoItem] = []

    func devices(refresh: Bool) async -> [Device] { [] }
    func screenshot(_ device: Device, to url: URL) async throws {}
    func listPhotos(_ device: Device, limit: Int) async throws -> PhotoListing {
        PhotoListing(items: [], total: 0)
    }
    func exportPhotos(
        _ device: Device, jobs: [(item: PhotoItem, destination: URL)],
        onProgress: @MainActor (Int) -> Void
    ) async throws -> [String: String] {
        receivedDevice = device
        receivedItems = jobs.map(\.item)
        for (index, job) in jobs.enumerated() {
            try Task.checkCancellation()
            if !omitFiles { try Data(job.item.id.utf8).write(to: job.destination) }
            if disconnect { throw ShotFailure("设备已断开") }
            onProgress(index + 1)
        }
        if cancelAfterLastFile { withUnsafeCurrentTask { $0?.cancel() } }
        return Dictionary(uniqueKeysWithValues: failures.map { ($0, "下载失败") })
    }
}

@MainActor
final class PhotoPreviewTests: XCTestCase {
    private var root: URL!
    private let device = Device(platform: .ios, serial: "PREVIEW", name: "Preview", model: nil, osVersion: nil, connection: .usb)
    private let items = [
        PhotoItem(id: "/DCIM/101APPLE/same.MOV", size: 10, date: .distantPast),
        PhotoItem(id: "/DCIM/100APPLE/same.MOV", size: 20, date: .distantPast),
        PhotoItem(id: "/DCIM/100APPLE/image.HEIC", size: 30, date: .distantPast),
    ]

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("preview-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func assertEmptyRoot(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [], file: file, line: line)
    }

    func testMixedPreviewKeepsSnapshotOrderAndUniqueNames() async throws {
        let provider = PreviewProvider()
        var progress: [Int] = []
        let session = try await PhotoPreviewSession.prepare(items, device: device, provider: provider, root: root) {
            progress.append($0)
        }
        XCTAssertEqual(provider.receivedDevice?.key, device.key)
        XCTAssertEqual(provider.receivedItems, items)
        XCTAssertEqual(session.urls.map(\.lastPathComponent), ["same.MOV", "same_2.MOV", "image.HEIC"])
        XCTAssertEqual(progress, [1, 2, 3])
        XCTAssertEqual(session.failureCount, 0)
        for (url, item) in zip(session.urls, items) {
            XCTAssertEqual(try Data(contentsOf: url), Data(item.id.utf8))
        }
        session.cleanup()
        try assertEmptyRoot()
    }

    func testPartialFailureExcludesFailedAndMissingFiles() async throws {
        let provider = PreviewProvider()
        provider.failures = [items[1].id]
        let session = try await PhotoPreviewSession.prepare(items, device: device, provider: provider, root: root) { _ in }
        XCTAssertEqual(session.urls.map(\.lastPathComponent), ["same.MOV", "image.HEIC"])
        XCTAssertEqual(session.failureCount, 1)
        session.cleanup()
        try assertEmptyRoot()
    }

    func testAllFailuresAndDisconnectCleanPartialDownloads() async throws {
        for disconnect in [false, true] {
            let provider = PreviewProvider()
            provider.failures = Set(items.map(\.id))
            provider.disconnect = disconnect
            do {
                _ = try await PhotoPreviewSession.prepare(items, device: device, provider: provider, root: root) { _ in }
                XCTFail("应报告预览失败")
            } catch { XCTAssertTrue(error is ShotFailure) }
            try assertEmptyRoot()
        }
    }

    func testMissingOutputDoesNotOpenPreview() async throws {
        let provider = PreviewProvider()
        provider.omitFiles = true
        do {
            _ = try await PhotoPreviewSession.prepare(items, device: device, provider: provider, root: root) { _ in }
            XCTFail("不能预览不存在的文件")
        } catch { XCTAssertTrue(error is ShotFailure) }
        try assertEmptyRoot()
    }

    func testCancellationDuringFinalFileDoesNotReturnSession() async throws {
        let provider = PreviewProvider()
        provider.cancelAfterLastFile = true
        let task = Task { @MainActor in
            try await PhotoPreviewSession.prepare(items, device: device, provider: provider, root: root) { _ in }
        }
        do {
            _ = try await task.value
            XCTFail("取消后不能展示预览")
        } catch { XCTAssertTrue(error is CancellationError) }
        try assertEmptyRoot()
    }

    func testReplacingOrReleasingSessionsCleansTemporaryFiles() async throws {
        let provider = PreviewProvider()
        var first: PhotoPreviewSession? = try await PhotoPreviewSession.prepare(items, device: device, provider: provider, root: root) { _ in }
        let firstDirectory = try XCTUnwrap(first?.directory)
        let second = try await PhotoPreviewSession.prepare(items, device: device, provider: provider, root: root) { _ in }
        XCTAssertNotEqual(firstDirectory, second.directory)
        first = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.directory.path))
        second.cleanup()
        try assertEmptyRoot()
    }
}

@MainActor
final class IOSMediaBatchTests: XCTestCase {
    func testVideosAreIndividualRequestsAndImagesStayInBatches() {
        let names = (0..<10).map { "\($0).HEIC" } + ["one.MOV", "two.mp4", "last.jpg"]
        let items = names.map { PhotoItem(id: "/DCIM/100APPLE/\($0)", size: 100, date: .distantPast) }
        let jobs = PhotoNaming.exportJobs(items, to: URL(fileURLWithPath: "/tmp"))
        let batches = IOSProvider.transferBatches(jobs)
        XCTAssertEqual(batches.map(\.count), [8, 2, 1, 1, 1])
        XCTAssertEqual(batches.flatMap { $0.map(\.item.id) }, items.map(\.id))
        XCTAssertEqual(batches.map { IOSProvider.pullTimeout(for: $0) }, [270, 270, 930, 930, 270])
        XCTAssertEqual(PhotoNaming.transferTimeout(for: "one.MOV"), 900)
        XCTAssertEqual(PhotoNaming.transferTimeout(for: "last.jpg"), 300)
    }
}

@MainActor
final class HelperQueueTests: XCTestCase {
    func testQueuedRefreshTimeoutStartsAfterVideoRequestCompletes() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("helper-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("helper.py")
        try """
        import json, sys, time
        for line in sys.stdin:
            req = json.loads(line)
            if req['cmd'] == 'photos_pull':
                time.sleep(0.4)
            print(json.dumps({'id': req['id'], 'ok': True, 'cmd': req['cmd']}), flush=True)
        """.write(to: script, atomically: true, encoding: .utf8)
        let oldPython = ProcessInfo.processInfo.environment["SCREENTOOLS_PYTHON"]
        let oldHelper = ProcessInfo.processInfo.environment["SCREENTOOLS_HELPER"]
        setenv("SCREENTOOLS_PYTHON", "/usr/bin/python3", 1)
        setenv("SCREENTOOLS_HELPER", script.path, 1)
        defer {
            if let oldPython { setenv("SCREENTOOLS_PYTHON", oldPython, 1) } else { unsetenv("SCREENTOOLS_PYTHON") }
            if let oldHelper { setenv("SCREENTOOLS_HELPER", oldHelper, 1) } else { unsetenv("SCREENTOOLS_HELPER") }
        }
        let helper = HelperClient()
        defer { helper.stop() }
        let video = Task { await helper.send("photos_pull", timeout: 5) }
        try await Task.sleep(nanoseconds: 30_000_000)
        let refresh = await helper.send("list", timeout: 0.15)
        let transfer = await video.value
        XCTAssertEqual(transfer["ok"] as? Bool, true)
        XCTAssertEqual(refresh["ok"] as? Bool, true)
        XCTAssertEqual(refresh["cmd"] as? String, "list")
    }
}

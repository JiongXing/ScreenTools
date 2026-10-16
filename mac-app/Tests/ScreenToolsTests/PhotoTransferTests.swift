import XCTest
@testable import ScreenTools

@MainActor
final class PhotoNamingTests: XCTestCase {
    func testParsePhotoList() {
        let text = """
        1700000100 2048 /sdcard/DCIM/Camera/IMG 2.jpg
        1700000200 10 /sdcard/DCIM/.thumbnails/x.jpg
        1700000250 10 /sdcard/DCIM/Camera/.trashed-1-IMG.jpg
        1700000300 99 /sdcard/Pictures/Screenshots/S.PNG
        1700000400 5 /sdcard/DCIM/Camera/clip.mp4
        garbage line
        """
        let items = AndroidProvider.parsePhotoList(text)
        XCTAssertEqual(items.map(\.id), ["/sdcard/Pictures/Screenshots/S.PNG", "/sdcard/DCIM/Camera/IMG 2.jpg"])
        XCTAssertEqual(items[1].size, 2048)
        XCTAssertEqual(items[1].name, "IMG 2.jpg")
        XCTAssertEqual(items[1].date, Date(timeIntervalSince1970: 1700000100))
    }

    func testShellQuote() {
        XCTAssertEqual(AndroidProvider.shellQuote("a b"), "'a b'")
        XCTAssertEqual(AndroidProvider.shellQuote("it's"), "'it'\\''s'")
    }

    func testSafeName() {
        XCTAssertEqual(PhotoNaming.safeName("my pic's (1).jpg"), "my_pic_s__1_.jpg")
        XCTAssertEqual(PhotoNaming.safeName("照片 1.heic"), "照片_1.heic")
        XCTAssertEqual(PhotoNaming.safeName("..."), "image")
    }

    func testUniqueName() {
        XCTAssertEqual(PhotoNaming.unique("a.jpg") { _ in false }, "a.jpg")
        XCTAssertEqual(PhotoNaming.unique("a.jpg") { ["a.jpg", "a_2.jpg"].contains($0) }, "a_3.jpg")
        XCTAssertEqual(PhotoNaming.unique("noext") { $0 == "noext" }, "noext_2")
    }

    func testCollectImagesExpandsFolders() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pn-\(UUID().uuidString)")
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["a.jpg", "sub/b.HEIC", "sub/c.txt", ".hidden.png"] {
            try Data([1]).write(to: dir.appendingPathComponent(name))
        }
        let single = dir.appendingPathComponent("a.jpg")
        let found = PhotoNaming.collectImages(from: [dir, single]).map(\.lastPathComponent).sorted()
        XCTAssertEqual(found, ["a.jpg", "a.jpg", "b.HEIC"])
        XCTAssertTrue(PhotoNaming.collectImages(from: [dir.appendingPathComponent("nope.jpg")]).isEmpty)
    }
}

/// 用一个假的 adb 脚本走完 Android 的列表 / 导出 / 导入流程。
@MainActor
final class AndroidPhotoFlowTests: XCTestCase {
    private var dir: URL!
    private var log: URL!
    private var provider: AndroidProvider!
    private let device = Device(platform: .android, serial: "FAKE123", name: "Fake", model: nil, osVersion: nil, connection: .usb)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("adbtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        log = dir.appendingPathComponent("adb.log")
        let fixture = dir.appendingPathComponent("fixture.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: fixture)
        let script = """
        #!/bin/bash
        [ "$1" = "-s" ] && shift 2
        echo "$@" >> '\(log.path)'
        case "$1" in
          shell)
            case "$2" in
              find*) printf '1700000100 2048 /sdcard/DCIM/Camera/IMG 2.jpg\\n1700000300 99 /sdcard/Pictures/Screenshots/S.png\\n' ;;
              mkdir*) printf 'existing.jpg\\n' ;;
            esac ;;
          pull) cp '\(fixture.path)' "$3" ;;
        esac
        exit 0
        """
        let adb = dir.appendingPathComponent("adb")
        try script.write(to: adb, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adb.path)
        setenv("SCREENTOOLS_ADB", adb.path, 1)
        provider = AndroidProvider()
    }

    override func tearDown() {
        unsetenv("SCREENTOOLS_ADB")
        try? FileManager.default.removeItem(at: dir)
    }

    private var logLines: [String] {
        ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    func testListPhotos() async throws {
        let listing = try await provider.listPhotos(device, limit: 1)
        XCTAssertEqual(listing.total, 2)
        XCTAssertEqual(listing.items.map(\.name), ["S.png"])
    }

    func testExportPhotosKeepsDate() async throws {
        let all = try await provider.listPhotos(device, limit: 10).items
        let out = dir.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let jobs = all.map { (item: $0, destination: out.appendingPathComponent($0.name)) }
        var last = 0
        let failures = try await provider.exportPhotos(device, jobs: jobs) { last = $0 }
        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(last, 2)
        for job in jobs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: job.destination.path))
            let attrs = try FileManager.default.attributesOfItem(atPath: job.destination.path)
            XCTAssertEqual((attrs[.modificationDate] as? Date)?.timeIntervalSince1970, job.item.date.timeIntervalSince1970)
        }
        XCTAssertTrue(logLines.contains("pull /sdcard/DCIM/Camera/IMG 2.jpg \(out.path)/IMG 2.jpg"))
    }

    func testImportRenamesAndScans() async throws {
        let a = dir.appendingPathComponent("my pic's.jpg")
        let b = dir.appendingPathComponent("existing.jpg")
        try Data([1]).write(to: a)
        try Data([1]).write(to: b)
        var last = 0
        let failures = try await provider.importPhotos(device, files: [a, b]) { last = $0 }
        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(last, 2)
        let lines = logLines
        XCTAssertTrue(lines.contains("push \(a.path) /sdcard/Pictures/ScreenTools/my_pic_s.jpg"), lines.joined(separator: "\n"))
        XCTAssertTrue(lines.contains("push \(b.path) /sdcard/Pictures/ScreenTools/existing_2.jpg"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("shell am broadcast") && $0.contains("existing_2.jpg") })
    }
}

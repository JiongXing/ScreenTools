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
        XCTAssertEqual(items.map(\.id), ["/sdcard/DCIM/Camera/clip.mp4", "/sdcard/Pictures/Screenshots/S.PNG", "/sdcard/DCIM/Camera/IMG 2.jpg"])
        XCTAssertEqual(items[2].size, 2048)
        XCTAssertEqual(items[2].name, "IMG 2.jpg")
        XCTAssertEqual(items[2].date, Date(timeIntervalSince1970: 1700000100))
    }

    func testShellQuote() {
        XCTAssertEqual(AndroidProvider.shellQuote("a b"), "'a b'")
        XCTAssertEqual(AndroidProvider.shellQuote("it's"), "'it'\\''s'")
    }

    func testSupportedMediaTypesAndHiddenImports() throws {
        for ext in ["mp4", "MOV", "m4v", "3GP", "3g2", "AVI", "mkv", "WebM"] {
            XCTAssertTrue(PhotoNaming.isMedia("clip.\(ext)"))
            XCTAssertTrue(PhotoNaming.isVideo("clip.\(ext)"))
            XCTAssertFalse(PhotoNaming.isImage("clip.\(ext)"))
        }
        for ext in ["JPG", "jpeg", "PNG", "heic", "heif", "gif", "tif", "tiff", "dng", "webp", "bmp"] {
            XCTAssertTrue(PhotoNaming.isMedia("photo.\(ext)"))
            XCTAssertFalse(PhotoNaming.isVideo("photo.\(ext)"))
        }
        XCTAssertFalse(PhotoNaming.isMedia("clip.mp4.txt"))
        let hidden = FileManager.default.temporaryDirectory.appendingPathComponent(".\(UUID().uuidString).MOV")
        try Data([1]).write(to: hidden)
        defer { try? FileManager.default.removeItem(at: hidden) }
        XCTAssertTrue(PhotoNaming.collectMedia(from: [hidden]).isEmpty)
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

    func testCollectMediaExpandsFolders() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pn-\(UUID().uuidString)")
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["a.jpg", "sub/b.HEIC", "sub/c.txt", ".hidden.png", "sub/clip.MOV", "sub/.hidden.mp4"] {
            try Data([1]).write(to: dir.appendingPathComponent(name))
        }
        let single = dir.appendingPathComponent("a.jpg")
        let found = PhotoNaming.collectMedia(from: [dir, single]).map(\.lastPathComponent).sorted()
        XCTAssertEqual(found, ["a.jpg", "a.jpg", "b.HEIC", "clip.MOV"])
        XCTAssertTrue(PhotoNaming.collectMedia(from: [dir.appendingPathComponent("nope.jpg")]).isEmpty)
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
              find*) printf '1700000100 2048 /sdcard/DCIM/Camera/IMG 2.jpg\\n1700000300 99 /sdcard/Pictures/Screenshots/S.png\\n1700000400 3 /sdcard/Movies/clip.MP4\\n' ;;
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
        XCTAssertEqual(listing.total, 3)
        XCTAssertEqual(listing.items.map(\.name), ["clip.MP4"])
    }

    func testExportPhotosKeepsDate() async throws {
        let all = try await provider.listPhotos(device, limit: 10).items
        let out = dir.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let jobs = all.map { (item: $0, destination: out.appendingPathComponent($0.name)) }
        var last = 0
        let failures = try await provider.exportPhotos(device, jobs: jobs) { last = $0 }
        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(last, 3)
        for job in jobs {
            XCTAssertEqual(try Data(contentsOf: job.destination), Data([0xFF, 0xD8, 0xFF]))
            let attrs = try FileManager.default.attributesOfItem(atPath: job.destination.path)
            XCTAssertEqual((attrs[.modificationDate] as? Date)?.timeIntervalSince1970, job.item.date.timeIntervalSince1970)
        }
        XCTAssertTrue(logLines.contains("pull /sdcard/DCIM/Camera/IMG 2.jpg \(out.path)/IMG 2.jpg"))
    }

    func testImportRenamesAndScans() async throws {
        let a = dir.appendingPathComponent("my pic's.jpg")
        let b = dir.appendingPathComponent("existing.jpg")
        let video = dir.appendingPathComponent("clip.MOV")
        try Data([1, 2, 3]).write(to: video)
        try Data([1]).write(to: a)
        try Data([1]).write(to: b)
        var last = 0
        let failures = try await provider.importPhotos(device, files: [a, b, video]) { last = $0 }
        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(last, 3)
        let lines = logLines
        XCTAssertTrue(lines.contains("push \(a.path) /sdcard/Pictures/ScreenTools/my_pic_s.jpg"), lines.joined(separator: "\n"))
        XCTAssertTrue(lines.contains("push \(b.path) /sdcard/Pictures/ScreenTools/existing_2.jpg"))
        XCTAssertTrue(lines.contains("push \(video.path) /sdcard/Pictures/ScreenTools/clip.MOV"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("shell am broadcast") && $0.contains("clip.MOV") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("shell am broadcast") && $0.contains("existing_2.jpg") })
    }
}

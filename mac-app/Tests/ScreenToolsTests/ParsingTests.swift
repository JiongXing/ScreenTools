import Carbon
import XCTest
@testable import ScreenTools

@MainActor
final class ParsingTests: XCTestCase {
    func testParseDevices() {
        let text = """
        List of devices attached
        R58M123ABC  device usb:1-1 product:a52q model:SM_A525F device:a52q transport_id:2
        emulator-5554\tunauthorized transport_id:3
        0123456789 no permissions usb:1-2
        * daemon started successfully
        """
        let entries = AndroidProvider.parseDevices(text)
        XCTAssertEqual(entries.map(\.serial), ["R58M123ABC", "emulator-5554", "0123456789"])
        XCTAssertEqual(entries.map(\.state), ["device", "unauthorized", "no permissions"])
        XCTAssertEqual(entries[0].model, "SM_A525F")
        XCTAssertNil(entries[1].model)
    }

    func testIsWireless() {
        XCTAssertTrue(AndroidProvider.isWireless("192.168.1.5:5555"))
        XCTAssertTrue(AndroidProvider.isWireless("adb-XYZ._adb-tls-connect._tcp"))
        XCTAssertFalse(AndroidProvider.isWireless("R58M123ABC"))
    }

    func testProblemMapping() {
        XCTAssertNil(AndroidProvider.problem(forState: "device"))
        XCTAssertNotNil(AndroidProvider.problem(forState: "offline"))
        XCTAssertNotNil(AndroidProvider.problem(forError: "error: device unauthorized."))
        XCTAssertNil(AndroidProvider.problem(forError: "something else"))
    }

    func testFilePrefixAndKey() {
        let ipad = Device(platform: .ios, serial: "U1", name: "x", model: "iPad Pro", osVersion: "17.5", connection: .usb)
        XCTAssertEqual(ipad.filePrefix, "iPad")
        XCTAssertEqual(ipad.key, "ios:U1")
        XCTAssertEqual(ipad.detail, "iPad Pro · iOS 17.5 · USB")
    }

    func testAutoChoicePrefersUsableThenUSB() {
        // autoChoice 依赖 devices，无设备时应为 nil
        XCTAssertNil(DeviceManager().autoChoice)
    }

    func testHotKeyDisplay() {
        XCTAssertEqual(HotKeySpec(keyCode: 7, modifiers: cmdKey | shiftKey, label: "X").display, "⇧⌘X")
        XCTAssertEqual(HotKeySpec(keyCode: 7, modifiers: cmdKey | shiftKey | optionKey, label: "X").display, "⌥⇧⌘X")
    }

    func testHotKeyRoundTrip() throws {
        let spec = HotKeySpec(keyCode: 1, modifiers: 256, label: "S")
        let decoded = try JSONDecoder().decode(HotKeySpec.self, from: JSONEncoder().encode(spec))
        XCTAssertEqual(decoded, spec)
    }

    func testJPEGQualityClamped() {
        let old = Settings.jpegQuality
        defer { Settings.jpegQuality = old }
        Settings.jpegQuality = 5
        XCTAssertEqual(Settings.jpegQuality, 1)
    }
}

import XCTest
@testable import ScreenTools

@MainActor
final class LiveClipboardTests: XCTestCase {
    func testAndroidClipboardRoundTrip() async throws {
        guard let serial = ProcessInfo.processInfo.environment["SCREENTOOLS_LIVE_ANDROID_CLIPBOARD"] else {
            throw XCTSkip("显式设置 SCREENTOOLS_LIVE_ANDROID_CLIPBOARD 才访问真机剪贴板")
        }
        let provider = AndroidProvider()
        defer { provider.stopClipboard() }
        let devices = await provider.devices(refresh: true)
        let device = try XCTUnwrap(devices.first { $0.serial == serial })
        guard let original = try await provider.readClipboard(device) else {
            throw XCTSkip("原剪贴板没有可完整备份的文本，未执行写入")
        }
        do {
            for value in ["ScreenTools 调试🧪\n'引号' \"双引号\"\nhttps://example.com/?a=1&b=2", "",
                          String(repeating: "长文本🧪\n", count: 3000), "ScreenTools repeated", "ScreenTools repeated"] {
                try await provider.writeClipboard(device, text: value)
                let result = try await provider.readClipboard(device)
                XCTAssertTrue(result == value, "真机往返文本应保持一致")
            }
        } catch {
            try await provider.writeClipboard(device, text: original)
            throw error
        }
        try await provider.writeClipboard(device, text: original)
        let restored = try await provider.readClipboard(device)
        XCTAssertTrue(restored == original, "原剪贴板文本应恢复")
    }
}

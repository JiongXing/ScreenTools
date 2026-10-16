# ScreenTools（屏幕工具箱）

- 工程结构、构建、使用与调试见 mac-app/README.md。
- 仅支持 Apple 芯片，最低 macOS 13。构建执行 `mac-app/scripts/build.sh`，测试执行 `cd mac-app && swift test`。
- 屏幕压暗保持遮罩方案和全局快捷键 ⌃⌥⌘B（压暗/恢复）、⌃⌥⌘R（始终恢复），不改为调节硬件背光。
- 编译、签名、`--self-check` 通过不能代表多屏实际压暗与恢复已验证；修改压暗行为后须在多屏环境实测。

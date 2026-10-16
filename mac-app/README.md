# 屏幕工具箱（ScreenTools）

一个 macOS 小工具箱，目前有两个功能（顶部切换）：

- **手机截图**：把连在这台 Mac 上的手机当前画面截下来，支持 **iPhone / iPad 和 Android**。截好的图会保存到「下载」文件夹（可改）、复制到剪贴板；可选用「预览」打开。
- **屏幕压暗**：用可穿透鼠标的黑色遮罩临时压暗所有活动屏幕，不修改硬件背光（由原 ScreenDimmer 合并而来）。

它是一个普通的 Dock 应用，**没有菜单栏图标**，所有功能都在主窗口里：
- 打开后显示主窗口：左边是设备列表，右边是最近一张截图的预览和「截图（JPEG）」「截图（PNG）」「复制」「显示」「打开」按钮，下面是最近 8 张截图的历史。
- **⌘W 关闭窗口但不退出进程**，点 Dock 图标可以重新打开窗口；⌘Q 退出；⌘, 打开设置。
- 快捷键**默认不设置**，需要时在「设置」里为 JPEG / PNG 截图各设一个。截图快捷键**只在屏幕工具箱处于前台时有效**，不是全局快捷键。
- 在后台时，可以用下面的 `screentools://` 链接从快捷指令、Raycast 等工具触发截图或压暗。

- 不需要管理员密码，不安装任何后台服务，不需要安装 Xcode 或 Android Studio
- 同时连着好几台手机时，在主窗口左侧选择截哪一台（默认「自动选择」：优先能截图的，其次优先数据线连接的）
- 系统要求：macOS 13 或以上，Apple 芯片（M 系列）Mac

---

## 安装

1. 打开 `ScreenTools.dmg`，把「屏幕工具箱」拖进「应用程序」文件夹。
2. 第一次打开时，macOS 会提示「无法验证开发者」，因为这个 App 还没有经过 Apple 公证：
   1. 先双击打开一次，在弹窗里点「完成」（不要点「移到废纸篓」）。
   2. 打开「系统设置 → 隐私与安全性」，滚到最下面，在「已阻止 屏幕工具箱」旁边点「仍要打开」，然后输入密码确认。
   3. 以后再打开就不会提示了。
3. 打开后会显示主窗口，左侧就是当前连着的手机。
4. 想开机自动运行，在「设置」里打开「开机自动启动」。


## 手机端准备（每台手机只需做一次）

### iPhone / iPad（需要 iOS 17.4 或以上；iOS 16 及以下也可以用）
1. **信任这台电脑**：用数据线连接 Mac，解锁手机，在弹窗里点「信任」并输入锁屏密码。
2. **打开开发者模式**：「设置 → 隐私与安全性 → 开发者模式」，打开开关，手机会重启；重启后按提示点「打开」并输入密码。
   - 设置里找不到这个选项？用数据线连接 Mac，打开 屏幕工具箱 的主窗口，这个选项就会出现。
3. 信任过以后，手机和电脑在同一个 Wi‑Fi 下时，不插线也能截图。
4. 刷新设备列表（打开窗口或切回 App 时会自动刷新）只读取信息，不会主动弹出「信任此电脑」；点截图时才会发起配对。

### Android
1. **打开开发者选项**：「设置 → 关于手机」，连续点「版本号」（小米叫「MIUI 版本」/「OS 版本」）7 次。
2. **打开 USB 调试**：「设置 → 系统 → 开发者选项」，打开「USB 调试」。
3. 用数据线连接 Mac，在手机弹出的「允许 USB 调试吗？」里勾选「始终允许」，然后点「允许」。
4. 不同品牌的注意事项：
   - **三星**：如果开了「自动拦截器」，需要关闭其中的「阻止通过 USB 线发出的命令」。
   - **华为**：纯血鸿蒙（HarmonyOS NEXT / 鸿蒙 5 及以上）暂不支持；HarmonyOS 2–4 可以用。
   - Android 11 及以上，电脑授权超过 7 天不用会被自动撤销，到时重新点一次「允许」即可。也可以在开发者选项里关掉「自动撤消 adb 授权」。
5. 银行、支付、部分视频 App 禁止截屏，截出来会是全黑的，屏幕工具箱 会提醒你。

## 第一次使用时可能出现的系统弹窗

| 弹窗 | 原因 | 建议 |
|---|---|---|
| 「屏幕工具箱 想访问『下载』文件夹中的文件」 | 截图保存在「下载」文件夹 | 点「允许」，只问一次 |
| 「屏幕工具箱 想发送通知」 | 截图失败时用通知告诉你原因 | 建议允许 |
| 「屏幕工具箱 想查找本地网络上的设备」 | 通过 Wi‑Fi 连接手机时 | 点「允许」 |

## 界面说明

### 主窗口
- **设备**（左栏）：
  - 点一台手机就固定截那一台，或选底部的「自动选择」。
  - 设备下方的灰色小字是机型、系统版本和连接方式；如果是橙色，说明这台手机现在截不了，橙色文字就是原因和解决方法。
  - 「刷新设备列表」：刚插上手机时可以点一下。打开窗口、从别的 App 切回来时也会自动刷新。
- **预览与操作**（右侧）：「截图（JPEG）」是压缩版（质量默认 80%），「截图（PNG）」是原图。截完后「复制」重新放进剪贴板，「显示」在 Finder 中定位文件，「打开」用默认看图程序打开。
- **最近**：最近 8 张 屏幕工具箱 截的图，点缩略图可在左侧预览。历史记在 App 的偏好设置里，重开 App 仍在，已被删除的文件会自动忽略。它记录的是 屏幕工具箱 自己截过的图，不会扫描「下载」文件夹。
- **底部状态栏**：显示保存位置；「截图后用预览打开」默认**不勾选**；右下角齿轮打开设置。

### 设置（⌘,）
- **快捷键**：默认都未设置。点按钮后按下组合键（需含 ⌘、⌃ 或 ⌥），Esc 取消，点 ✕ 清除。只在 屏幕工具箱 处于前台时有效。
- **保存位置**：默认「下载」，可改成任意文件夹。
- **JPEG 质量**：30%–100%，默认 80%。
- **开机自动启动**。
- **允许外部工具通过 `screentools://` 触发截图 / 压暗**：默认开启，不需要时可关闭。

### 键盘
| 按键 | 作用 |
|---|---|
| ⌘W | 关闭当前窗口，进程继续运行（点 Dock 图标重新打开） |
| ⌘Q | 退出 屏幕工具箱 |
| ⌘, | 打开设置 |
| 自定义 | 在设置里设置的截图快捷键（仅前台有效） |

## 屏幕压暗

在主窗口顶部切到「屏幕压暗」：

- 「压暗所有屏幕 / 恢复所有屏幕」：给每块正在使用的屏幕盖上黑色半透明遮罩；「始终恢复」无论当前状态都移除遮罩。
- 压暗程度：柔和 85% / 很暗 95% / 最低 98%（默认），会记住选择。
- **全局快捷键（任何位置都有效，固定不可改）**：`⌃⌥⌘B` 压暗 / 恢复；`⌃⌥⌘R` 始终恢复。若被其它应用占用，页面上会提示，仍可点按钮操作。
- 支持 MacBook 内置屏和多块外接屏；压暗期间接入屏幕或改变排列，会自动重新匹配。鼠标可穿过遮罩正常操作。
- 退出应用、电脑睡眠或唤醒都会恢复；强制退出时遮罩也会随进程消失。
- 这是视觉压暗，**不调节硬件背光、不关闭显示器、不等同于节能**。不需要辅助功能或屏幕录制权限。
- 窗口关闭后（只剩 Dock 图标）压暗状态和全局快捷键依然有效。

命令行 `build/ScreenTools.app/Contents/MacOS/ScreenTools --self-check`，通过则退出码为 0。

## 常见问题

| 提示 | 怎么办 |
|---|---|
| 没有检测到手机 | 插上数据线；iPhone 也可以和电脑连同一个 Wi‑Fi（前提是之前信任过） |
| iPhone 尚未信任此电脑 | 插线、解锁手机，在弹窗中点「信任」 |
| 未开启开发者模式 | 见上面「iPhone / iPad」第 2 步 |
| 挂载开发者镜像失败 | 手机每次重启后，第一次截图要联网下载一个约 15 MB 的组件，请检查网络后重试 |
| Android 显示「未授权」 | 解锁手机，在「允许 USB 调试吗？」弹窗中点「允许」；没有弹窗就重新插拔数据线 |
| Android 显示「设备离线」 | 重新插拔数据线，或者在开发者选项里把 USB 调试关掉再打开 |
| 截图是全黑的 | 当前页面禁止截屏，或者手机已经息屏 |
| 「某某设备」未连接 | 你固定选择的那台手机不在线：重新连接，或在主窗口左侧改回「自动选择」 |

日志文件在 `~/Library/Logs/ScreenTools/` 下：`app.log` 是 App 的日志，`ios-helper.log` 是 iPhone 连接相关的日志。反馈问题时请附上这两个文件。

## 给其它工具调用

屏幕工具箱 在运行时（包括窗口被关掉、只剩 Dock 图标的状态），打开下面的链接就能触发截图，可以接到「快捷指令」、Raycast、Alfred 等工具里：

```
screentools://capture              截 JPEG
screentools://capture?format=png   截 PNG 原图
screentools://show                 显示主窗口
screentools://dim                  压暗 / 恢复所有屏幕（切换）
screentools://restore              恢复所有屏幕
```

例如在终端里：`open "screentools://capture?format=png"`。如果不希望被其它程序触发，在「设置」里关掉「允许外部工具通过 screentools:// 触发截图 / 压暗」。

---

## 开发者说明

```
mac-app/
  Package.swift                 SwiftPM 工程（Dock 应用，target：ScreenTools，另有 ScreenToolsTests）
  Sources/ScreenTools/
    App.swift / AppDelegate.swift  入口；窗口、⌘W/⌘Q/⌘,、应用内快捷键、URL Scheme
    MainView.swift              主窗口（顶部切换「手机截图 / 屏幕压暗」；设备列表、预览、操作、历史、状态栏）
    SettingsView.swift          设置窗口（快捷键录入、保存位置、JPEG 质量等）
    Scaled.swift                界面放大倍数 UIScale 与放大版按钮、复选框、滑块
    Settings.swift              偏好设置（UserDefaults）与 HotKeySpec
    Device.swift                设备模型 + DeviceProvider 协议
    DeviceManager.swift         汇总各平台设备、记住所选设备、自动选择规则
    IOSProvider.swift           iOS：通过 Python 辅助进程
    AndroidProvider.swift       Android：调用 adb
    HelperClient.swift          管理 Python 辅助进程（JSON-lines 通信，超时会重启它）
    ProcessRunner.swift         异步运行命令行程序（带超时）
    ScreenDimmer.swift          屏幕压暗：遮罩窗口、Carbon 全局热键 ⌃⌥⌘B/R、屏幕变化/睡眠唤醒处理、--self-check
    DimmerView.swift            「屏幕压暗」页（压暗/恢复、压暗程度、快捷键说明）
    ShotController.swift        截图流程：选设备 → 截图 → 保存 → 剪贴板 → 历史（编码在后台线程）
    ImageOutput.swift           JPEG/PNG 编码、文件命名、剪贴板、黑屏检测
    Notifier.swift / AppLog.swift  通知与日志
  Tests/ScreenToolsTests/         单元测试（adb 输出解析、设备模型、快捷键编码等）
  helper/ios_helper.py          iOS 辅助进程（pymobiledevice3 用户态隧道 + DVT 截图）
  Resources/                    Info.plist（普通 Dock 应用，非 LSUIElement）、AppIcon.icns、签名用 entitlements
  scripts/build.sh              构建 .app 和 .dmg
  scripts/make_icon.sh/.swift   重新生成图标
```

### 工作原理

**iOS**：App 启动后会拉起一个用内置 Python 写的辅助进程 `ios_helper.py`。截图时，它先通过 usbmuxd 找到设备，然后：
1. iOS 17.4 及以上：用 pymobiledevice3 的 `UserspaceRsdTunnel` 在进程内建一条隧道，不需要 root。这条隧道会一直保留复用，空闲 10 分钟后自动关闭；每个进程同时只能有一条隧道，换设备时会先关掉旧的再重建。
2. 调用 `com.apple.instruments.server.services.screenshot` 截图。
3. 如果截图服务不可用，就先检查开发者模式，再自动挂载开发者镜像，然后重试。

**Android**：在 Swift 里直接调用 adb：
1. `adb devices -l` 列出设备。
2. `adb shell getprop …` 读取设备名和系统版本。
3. `adb -s <序列号> exec-out screencap -p` 截取 PNG。
4. adb 的查找顺序：环境变量 `SCREENTOOLS_ADB` → `ANDROID_HOME` → `~/Library/Android/sdk/platform-tools` → Homebrew → App 内置的 `Contents/Helpers/adb`。之所以优先用电脑上已有的 adb，是为了避免两个不同版本的 adb 后台服务互相踢掉对方。

**iOS 辅助进程协议**（每行一个 JSON）：

```
→ {"id":1,"cmd":"list","refresh":true}
← {"id":1,"ok":true,"devices":[{"udid":"…","name":"…","version":"26.6.2","connection":"Wi-Fi","devMode":true}]}
→ {"id":2,"cmd":"screenshot","udid":"…","out":"/tmp/x.png"}
← {"id":2,"ok":true,"device":{…},"ms":420}
← {"id":2,"ok":false,"code":"DEV_MODE_OFF","message":"…"}
```

### 构建

需要：Xcode（或 Command Line Tools）、[uv](https://docs.astral.sh/uv/)，以及（可选）Android SDK 的 platform-tools（用来把 adb 打包进 App）。

```bash
mac-app/scripts/build.sh
```

- 构建产物：`mac-app/build/ScreenTools.app` 和 `mac-app/build/ScreenTools.dmg`。
- 默认使用 ad-hoc 签名。拿到「Developer ID Application」证书后：

```bash
SIGN_ID="Developer ID Application: XXX (TEAMID)" NOTARY_PROFILE=my-profile mac-app/scripts/build.sh
```

`NOTARY_PROFILE` 需要先用 `xcrun notarytool store-credentials` 保存。

关于内置 adb 的许可：adb 源码属于 AOSP，采用 Apache 2.0 许可，platform-tools 附带的许可声明会复制到 `Contents/Resources/adb-NOTICE.txt`。如果不想把 adb 打包进 App，用 `SKIP_ADB=1 mac-app/scripts/build.sh` 构建，App 就只会使用用户自己安装的 adb。

### 测试

```bash
cd mac-app && swift test
```

### 界面放大

界面尺寸、字号、图标都以「基础 pt × `UIScale.factor`」逐个放大（当前 1.5），不是整体位图缩放，所以不会模糊。想调整倍数，改 `Sources/ScreenTools/Scaled.swift` 里的 `UIScale.factor`；新增界面元素时请用 `S(...)` 和 `.font(.ui(...))`。

### 调试

```bash
# 单独运行 iOS 辅助进程，然后输入 {"id":1,"cmd":"list","refresh":true}
mac-app/build/ScreenTools.app/Contents/Resources/python/bin/python3 -I -B mac-app/helper/ios_helper.py

# 让 App 使用指定的 adb（例如测试用的假 adb）
open --env SCREENTOOLS_ADB=/path/to/adb mac-app/build/ScreenTools.app
```

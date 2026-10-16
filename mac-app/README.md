# PhoneShot

一个 macOS 菜单栏小工具。按一下快捷键，就能把连在这台 Mac 上的手机当前画面截下来，支持 **iPhone / iPad 和 Android**。截好的图会保存到「下载」文件夹、复制到剪贴板，并用「预览」打开。

| 快捷键 | 效果 |
|---|---|
| ⌘⇧X | 截图，保存为压缩版 JPEG（质量 80%） |
| ⌥⌘⇧X | 截图，保存为 PNG 原图 |

- 不需要管理员密码，不安装任何后台服务，不需要安装 Xcode 或 Android Studio
- 同时连着好几台手机时，可以在菜单里选择截哪一台（默认「自动选择」：优先能截图的，其次优先数据线连接的）
- 系统要求：macOS 13 或以上，Apple 芯片（M 系列）Mac

---

## 安装

1. 打开 `PhoneShot.dmg`，把「PhoneShot」拖进「应用程序」文件夹。
2. 第一次打开时，macOS 会提示「无法验证开发者」，因为这个 App 还没有经过 Apple 公证：
   1. 先双击打开一次，在弹窗里点「完成」（不要点「移到废纸篓」）。
   2. 打开「系统设置 → 隐私与安全性」，滚到最下面，在「已阻止 PhoneShot」旁边点「仍要打开」，然后输入密码确认。
   3. 以后再打开就不会提示了。
3. 打开后，菜单栏右上角会出现一个取景框图标。点开菜单，就能看到当前连着的手机。
4. 想开机自动运行，就在菜单里勾选「开机自动启动」。

> 如果你装过旧版脚本（`install_iphone_shot.sh`），请先运行 `bash scripts/uninstall_legacy.sh` 卸载，并删除「快捷指令」里的两个截图快捷指令，否则 ⌘⇧X 会冲突。

## 手机端准备（每台手机只需做一次）

### iPhone / iPad（需要 iOS 17.4 或以上；iOS 16 及以下也可以用）
1. **信任这台电脑**：用数据线连接 Mac，解锁手机，在弹窗里点「信任」并输入锁屏密码。
2. **打开开发者模式**：「设置 → 隐私与安全性 → 开发者模式」，打开开关，手机会重启；重启后按提示点「打开」并输入密码。
   - 设置里找不到这个选项？用数据线连接 Mac，点开 PhoneShot 的菜单栏图标，这个选项就会出现。
3. 信任过以后，手机和电脑在同一个 Wi‑Fi 下时，不插线也能截图。

### Android
1. **打开开发者选项**：「设置 → 关于手机」，连续点「版本号」（小米叫「MIUI 版本」/「OS 版本」）7 次。
2. **打开 USB 调试**：「设置 → 系统 → 开发者选项」，打开「USB 调试」。
3. 用数据线连接 Mac，在手机弹出的「允许 USB 调试吗？」里勾选「始终允许」，然后点「允许」。
4. 不同品牌的注意事项：
   - **三星**：如果开了「自动拦截器」，需要关闭其中的「阻止通过 USB 线发出的命令」。
   - **华为**：纯血鸿蒙（HarmonyOS NEXT / 鸿蒙 5 及以上）暂不支持；HarmonyOS 2–4 可以用。
   - Android 11 及以上，电脑授权超过 7 天不用会被自动撤销，到时重新点一次「允许」即可。也可以在开发者选项里关掉「自动撤消 adb 授权」。
5. 银行、支付、部分视频 App 禁止截屏，截出来会是全黑的，PhoneShot 会提醒你。

## 第一次使用时可能出现的系统弹窗

| 弹窗 | 原因 | 建议 |
|---|---|---|
| 「PhoneShot 想访问『下载』文件夹中的文件」 | 截图保存在「下载」文件夹 | 点「允许」，只问一次 |
| 「PhoneShot 想发送通知」 | 截图失败时用通知告诉你原因 | 建议允许 |
| 「PhoneShot 想查找本地网络上的设备」 | 通过 Wi‑Fi 连接手机时 | 点「允许」 |

## 菜单说明

- **截图设备**：
  - 选「自动选择」，或者固定某一台手机。
  - 设备下方的灰色小字是机型、系统版本和连接方式；如果是橙色，说明这台手机现在截不了，橙色文字就是原因和解决方法。
- **截图后用预览打开**：关掉以后只保存文件、复制到剪贴板，不弹预览窗口。
- **刷新设备列表**：刚插上手机时可以点一下。

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
| 「某某设备」未连接 | 你固定选择的那台手机不在线：重新连接，或在菜单里改回「自动选择」 |

日志文件在 `~/Library/Logs/PhoneShot/` 下：`app.log` 是 App 的日志，`ios-helper.log` 是 iPhone 连接相关的日志。反馈问题时请附上这两个文件。

## 给其它工具调用

打开下面的链接就能触发截图，可以接到「快捷指令」、Raycast、Alfred 等工具里：

```
phoneshot://capture              截 JPEG
phoneshot://capture?format=png   截 PNG 原图
```

例如在终端里：`open "phoneshot://capture?format=png"`

---

## 开发者说明

```
mac-app/
  Package.swift                 SwiftPM 工程（菜单栏 App，target：PhoneShot）
  Sources/PhoneShot/
    AppDelegate.swift           菜单栏图标、菜单（含设备选择）、快捷键和 URL Scheme
    Device.swift                设备模型 + DeviceProvider 协议
    DeviceManager.swift         汇总各平台设备、记住所选设备、自动选择规则
    IOSProvider.swift           iOS：通过 Python 辅助进程
    AndroidProvider.swift       Android：调用 adb
    HelperClient.swift          管理 Python 辅助进程（JSON-lines 通信）
    ProcessRunner.swift         异步运行命令行程序（带超时）
    ShotController.swift        截图流程：选设备 → 截图 → 保存 → 剪贴板 → 预览
    ImageOutput.swift           JPEG/PNG 编码、文件命名、剪贴板、黑屏检测
    HotKeyCenter.swift          Carbon 全局快捷键（不需要「辅助功能」权限）
    Notifier.swift / AppLog.swift  通知与日志
  helper/ios_helper.py          iOS 辅助进程（pymobiledevice3 用户态隧道 + DVT 截图）
  Resources/                    Info.plist、AppIcon.icns、签名用 entitlements
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
4. adb 的查找顺序：环境变量 `PHONESHOT_ADB` → `ANDROID_HOME` → `~/Library/Android/sdk/platform-tools` → Homebrew → App 内置的 `Contents/Helpers/adb`。之所以优先用电脑上已有的 adb，是为了避免两个不同版本的 adb 后台服务互相踢掉对方。

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

- 构建产物：`mac-app/build/PhoneShot.app` 和 `mac-app/build/PhoneShot.dmg`。
- 默认使用 ad-hoc 签名。拿到「Developer ID Application」证书后：

```bash
SIGN_ID="Developer ID Application: XXX (TEAMID)" NOTARY_PROFILE=my-profile mac-app/scripts/build.sh
```

`NOTARY_PROFILE` 需要先用 `xcrun notarytool store-credentials` 保存。

关于内置 adb 的许可：adb 源码属于 AOSP，采用 Apache 2.0 许可，platform-tools 附带的许可声明会复制到 `Contents/Resources/adb-NOTICE.txt`。如果不想把 adb 打包进 App，用 `SKIP_ADB=1 mac-app/scripts/build.sh` 构建，App 就只会使用用户自己安装的 adb。

### 调试

```bash
# 单独运行 iOS 辅助进程，然后输入 {"id":1,"cmd":"list","refresh":true}
mac-app/build/PhoneShot.app/Contents/Resources/python/bin/python3 -I -B mac-app/helper/ios_helper.py

# 让 App 使用指定的 adb（例如测试用的假 adb）
open --env PHONESHOT_ADB=/path/to/adb mac-app/build/PhoneShot.app
```

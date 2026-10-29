# 屏幕工具箱（ScreenTools）

一个 macOS 小工具箱，目前有四个功能（顶部切换）：

- **手机截图**：把连在这台 Mac 上的手机当前画面截下来，支持 **iPhone / iPad 和 Android**。截好的图会保存到「下载」文件夹（可改）、复制到剪贴板；可选用「预览」打开。
- **手机相册**：把手机相册里的图片和视频**导出到这台 Mac**，也可以把 Mac 上的图片和视频**传进手机相册**。Android 直接读写，iPhone 导出走数据线、导入走隔空投送（见下文）。
- **剪贴板**：手动读取、编辑和写入 Mac 与手机的文本或链接。Mac、Android 和 iPhone 均已通过本机实测（iPhone 依赖设备提供的开发者剪贴板服务，见下文）。
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

### 手机相册

在主窗口顶部切到「手机相册」，左侧选好设备（和截图共用同一份设备列表）：

- **导出到电脑**：列表里是手机相册最新的 500 项图片和视频（新的在前，可用 ⇧/⌘ 点击多选），点「导出所选」。文件保存在「保存位置」下的 `手机相册` 文件夹（默认 `下载/手机相册`），文件名与手机上一致、重名自动加 `_2`，修改时间与手机上的一致。导出完成后可点「在 Finder 中显示」，导出中可以「取消」。
- **预览所选**：选中一项或多项后点「预览」，先下载到临时目录，再打开 macOS Quick Look 窗口，可切换图片和播放系统支持的视频。准备期间可取消（当前文件完成或超时后停止）；大视频首次预览需要等待。部分下载失败时仍会打开成功项并显示失败数量。关闭预览窗口后清理临时文件，异常退出的残留在下次启动清理。
- **传进手机**：点「导入到手机…」选择图片、视频或文件夹，也可以直接把文件/文件夹**拖进窗口**。图片支持 JPG、PNG、HEIC、GIF、WebP 等，视频支持 MP4、MOV、M4V、3GP、3G2、AVI、MKV、WebM，扩展名不区分大小写；文件夹会递归读取并忽略隐藏文件。
  - **Android**：图片和视频会传到手机的 `Pictures/ScreenTools` 文件夹，相册里出现名为「ScreenTools」的相簿，可能要等几秒。文件名里的空格、引号等会换成下划线，重名自动加 `_2`。
  - **iPhone / iPad**：苹果不允许 Mac 通过数据线直接写入「照片」，所以这里会打开**隔空投送**：在弹出的窗口里选这台手机，并在手机上点「接受」，系统支持的图片和视频会存进「照片」，其它格式的接收位置由 iOS 决定。需要 Mac 的蓝牙和 Wi‑Fi 打开；手机和 Mac 登录同一个 Apple 账号时一般会自动接收。
- iPhone 导出读取的是「相机胶卷」里**已经存在手机本地**的图片和视频（含截图）；「优化 iPhone 储存空间」后只在 iCloud 里的原图、共享相簿里的媒体读不到。读取相册不需要开发者模式，但需要信任过这台电脑，手机要解锁。
- 视频按原文件传输，不转码；能否播放取决于系统支持的编码。导入和导出视频单文件最长等待 15 分钟。
- 手机相册页的设备列表里，iPhone 下方若有「未开启开发者模式」的橙色提示，只影响截图，不影响相册。

### 剪贴板

在「手机相册」和「屏幕压暗」之间切到「剪贴板」，左侧选择手机，右侧编辑文字：

- **读取电脑 / 读取手机**：把对应剪贴板中的文本或链接放进编辑框。没有可读文本或读取失败时，保留编辑框原内容，并显示原因；空字符串与没有文本分别处理。
- **写入电脑 / 写入手机**：用编辑框当前内容替换对应剪贴板，空字符串也可写入；只写入，不会触发粘贴。
- 没有连接手机时，电脑读写仍可使用。手机操作期间显示目标与进度并禁用重复操作，开始时固定目标设备和文本。切换 Tab 保留草稿，退出进程后清除；没有历史记录、图片或自动同步。
- **Android**：需要 USB 调试授权；部分小米/红米机型还需开启「USB 调试（安全设置）」。内置 scrcpy 服务只建立控制通道，不传音视频、不自动亮屏、不注入复制/粘贴按键。写入收到确认后还会读回核对；每次操作结束清理连接、辅助进程和端口转发，下次重新建立。单次写入上限为 262130 字节 UTF-8。若设备不返回数据，会显示读取超时及可能原因，不把无响应判定为成功或空字符串。
- **iPhone**：需要 iOS 17.4 以上、信任这台 Mac、开发者模式及兼容的开发者镜像，并且设备实际提供 `com.apple.coredevice.pasteboardservice`。截图可用不代表剪贴板可用。首次可能需要联网挂载镜像；单次写入上限为 1 MiB UTF-8。只支持纯文本（含 emoji 和链接），不保留格式和图片。读取只请求每项的首类型：纯文本直接使用；备忘录复制的私有格式由 helper 直接解析出正文；其它格式（如 Safari 网页复制）不读取，直接提示在手机上粘贴到备忘录等文本编辑器后再复制。写入直接替换，不先读取现有内容；写入后读回核对，不自动重试写入。
- **iPhone 已知限制**：Safari 等网页复制的内容首类型只是个标记，纯文本要等手机生成 RTF 失败（约 64 秒）后才给出，系统 `devicectl` 同样慢，没有更快的接口，所以不支持。可在手机上粘贴到备忘录再复制，或用同一 Apple 账号的「通用剪贴板」（接力）后在 Mac 上点「读取电脑」。
- 日志只记录剪贴板操作状态和错误，不记录正文。实测环境、备份恢复和待验收项见 [剪贴板验收记录](docs/clipboard-validation.md)。

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

- 「压暗所有屏幕 / 恢复所有屏幕」：给每块正在使用的屏幕盖上黑色半透明遮罩，再点一次恢复。压暗后基本看不清界面，主要靠下面的快捷键恢复。
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
| 手机相册里看不到某些 iPhone 图片或视频 | 只显示存在手机本地的相机胶卷图片和视频；iCloud 里未下载的原图、共享相簿的图读不到，先在手机上下载 |
| 传到 Android 的图片或视频相册里没出现 | 等几秒或下拉刷新相册；也可在文件管理器里查看 `Pictures/ScreenTools` |
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
    MainView.swift              主窗口（手机截图 / 手机相册 / 剪贴板 / 屏幕压暗；共用设备列表）
    SettingsView.swift          设置窗口（快捷键录入、保存位置、JPEG 质量等）
    Scaled.swift                界面放大倍数 UIScale 与放大版按钮、复选框、滑块
    Settings.swift              偏好设置（UserDefaults）与 HotKeySpec
    Device.swift                设备模型 + DeviceProvider 协议
    DeviceManager.swift         汇总各平台设备、记住所选设备、自动选择规则
    IOSProvider.swift           iOS：通过 Python 辅助进程（截图、相册列表与导出）
    AndroidProvider.swift       Android：调用 adb（截图、相册列表、导出、导入）
    HelperClient.swift          管理 Python 辅助进程（JSON-lines 通信，超时会重启它）
    ProcessRunner.swift         异步运行命令行程序（带超时）
    ScreenDimmer.swift          屏幕压暗：遮罩窗口、Carbon 全局热键 ⌃⌥⌘B/R、屏幕变化/睡眠唤醒处理、--self-check
    DimmerView.swift            「屏幕压暗」页（压暗/恢复、压暗程度、快捷键说明）
    PhotosView.swift            「手机相册」页（图片/视频列表、导出、导入/拖入、预览）
    PhotoPreview.swift         临时预览下载、Quick Look 数据源与窗口响应链
    PhotoTransfer.swift         相册传输流程（列表、导出、导入、进度/取消）与文件名处理 PhotoNaming
    ClipboardController.swift  内存草稿、Mac NSPasteboard、设备目标快照与状态
    ClipboardView.swift        剪贴板编辑器与四个手动操作按钮
    AndroidClipboard.swift     scrcpy 控制协议、确认与读回核对、短时会话清理
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

**相册**：
- Android：`adb shell find /sdcard/DCIM /sdcard/Pictures /sdcard/Movies -type f -exec stat -c '%Y %s %n' {} +` 列出图片和视频（忽略隐藏文件和缩略图缓存），`adb pull` 导出；导入用 `adb push` 到 `/sdcard/Pictures/ScreenTools/`，再发 `MEDIA_SCANNER_SCAN_FILE` 广播通知相册刷新。
- iOS：辅助进程用 pymobiledevice3 的 `AfcService`（lockdown 的 `com.apple.afc`，只能访问 `/DCIM`）列出并拷贝图片和视频，不需要开发者模式和隧道。写入「照片」库没有公开的有线接口，所以导入走隔空投送（`NSSharingService(named: .sendViaAirDrop)`）。
- `afc` 模块导入时依赖 `xonsh`，所以 `build.sh` 不能把它从内置 Python 里删掉（构建时会验证 `import pymobiledevice3.services.afc`）。

**剪贴板**：Mac 使用 `NSPasteboard.general`。iOS 使用固定版本 `pymobiledevice3==11.26.0` 的 `PasteboardService`，复用用户态隧道；helper 新增 `clipboard_get` 与 `clipboard_set`，读取返回 `text: null` 表示无文本，`text: ""` 表示空字符串，备忘录的 `com.apple.notes.richtext`（`ICNotePasteboardData` 归档，正文在 `attributedStringData` protobuf 的字段 2）由 helper 解析。不发送 `RESOLVE`：电脑发出后手机不回复。Android 使用固定的官方 scrcpy-server v5.0.1（Apache 2.0），Swift 直接实现控制通道协议，用户无需安装 scrcpy 或手机 APK。

**iOS 辅助进程协议**（每行一个 JSON）：

```
→ {"id":1,"cmd":"list","refresh":true}
← {"id":1,"ok":true,"devices":[{"udid":"…","name":"…","version":"26.6.2","connection":"Wi-Fi","devMode":true}]}
→ {"id":2,"cmd":"screenshot","udid":"…","out":"/tmp/x.png"}
← {"id":2,"ok":true,"device":{…},"ms":420}
← {"id":2,"ok":false,"code":"DEV_MODE_OFF","message":"…"}
→ {"id":3,"cmd":"photos_list","udid":"…","limit":500}
← {"id":3,"ok":true,"photos":[{"path":"/DCIM/100APPLE/IMG_0001.HEIC","size":123,"mtime":1.7e9}],"total":1234}
→ {"id":4,"cmd":"photos_pull","udid":"…","items":[{"path":"/DCIM/100APPLE/IMG_0001.HEIC","out":"/Users/x/a.heic"}]}
← {"id":4,"ok":true,"results":[{"path":"…","ok":true}]}
→ {"id":5,"cmd":"clipboard_get","udid":"…"}
← {"id":5,"ok":true,"text":"文本或链接"}
→ {"id":6,"cmd":"clipboard_set","udid":"…","text":"文本或链接"}
← {"id":6,"ok":true}
```

### 构建

需要：Xcode（或 Command Line Tools）、[uv](https://docs.astral.sh/uv/)，以及（可选）Android SDK 的 platform-tools（用来把 adb 打包进 App）。

```bash
mac-app/scripts/build.sh
```

- 构建产物：`mac-app/build/ScreenTools.app` 和 `mac-app/build/ScreenTools.dmg`。
- 构建调用 `scripts/prepare_clipboard.sh`，从官方 GitHub release 下载 scrcpy-server v5.0.1 并缓存到 `build/dependencies/`；校验 SHA-256 `764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536` 后才打包。许可证随 App 放入 `Contents/Resources/scrcpy-LICENSE.txt`，运行时无需下载此组件。
- 默认使用 ad-hoc 签名。拿到「Developer ID Application」证书后：

```bash
SIGN_ID="Developer ID Application: XXX (TEAMID)" NOTARY_PROFILE=my-profile mac-app/scripts/build.sh
```

`NOTARY_PROFILE` 需要先用 `xcrun notarytool store-credentials` 保存。

关于内置 adb 的许可：adb 源码属于 AOSP，采用 Apache 2.0 许可，platform-tools 附带的许可声明会复制到 `Contents/Resources/adb-NOTICE.txt`。如果不想把 adb 打包进 App，用 `SKIP_ADB=1 mac-app/scripts/build.sh` 构建，App 就只会使用用户自己安装的 adb。

### 测试

```bash
cd mac-app && swift test
python3 -B -m unittest discover -s helper/tests -v
```

自动化测试覆盖媒体格式、混合列表与传输、iOS 视频批次和超时、预览下载失败/取消/清理，以及辅助进程请求排队。Quick Look 播放、手机相册入库和隔空投送接收需真机验证。

剪贴板自动测试覆盖中文、emoji、多行、引号、链接、长文本、空字符串、非文本和拒绝访问，以及 scrcpy 分包、长度边界、写入确认/核对、断线/超时及会话清理；Python 测试覆盖 helper 分发、服务缺失、写入前检查与超时后的隧道清理。它们不替代真机验收。

Android 真机测试默认跳过，先在手机复制可恢复的普通测试文本，再运行：

```bash
cd mac-app
SCREENTOOLS_SCRCPY_SERVER="$PWD/build/dependencies/scrcpy-server-v5.0.1" \
  SCREENTOOLS_LIVE_ANDROID_CLIPBOARD=<序列号> swift test --filter LiveClipboardTests
```

该测试在进程内备份并恢复原文本（不备份非文本表示），验证每次重新建立连接后的读写。iPhone 调试使用 `helper/tests/live_clipboard.py --help`；它先校验完整快照，无法完整备份时在写入前中止，不把缺失数据当作空剪贴板。

`LiveMediaTests` 默认跳过。设置 `SCREENTOOLS_LIVE_ANDROID=<序列号>` 和 `SCREENTOOLS_LIVE_MEDIA=<测试媒体目录>` 后，可用 `swift test --filter LiveMediaTests/testAndroidMediaRoundTrip` 验证真机导入/导出的大小与 SHA-256；目录需同时包含图片和视频，文件名应唯一，测试后需清理手机上的测试素材。iOS 设置 `SCREENTOOLS_LIVE_IOS=<UDID>`，并用 `SCREENTOOLS_PYTHON`、`SCREENTOOLS_HELPER` 指定内置 Python 与辅助脚本，再运行 `swift test --filter LiveMediaTests/testIOSLocalPhotoAndVideoExports`；该测试仅读取手机现有本地图片和视频。

本次验收结果与未完成项见 [相册媒体验收记录](docs/album-media-validation.md)。

### 界面放大

界面尺寸、字号、图标都以「基础 pt × `UIScale.factor`」逐个放大（当前 1.5），不是整体位图缩放，所以不会模糊。想调整倍数，改 `Sources/ScreenTools/Scaled.swift` 里的 `UIScale.factor`；新增界面元素时请用 `S(...)` 和 `.font(.ui(...))`。

### 调试

```bash
# 单独运行 iOS 辅助进程，然后输入 {"id":1,"cmd":"list","refresh":true}
mac-app/build/ScreenTools.app/Contents/Resources/python/bin/python3 -I -B mac-app/helper/ios_helper.py

# 让 App 使用指定的 adb（例如测试用的假 adb；单元测试里的相册流程就是用假 adb 脚本跑的）
open --env SCREENTOOLS_ADB=/path/to/adb mac-app/build/ScreenTools.app
```

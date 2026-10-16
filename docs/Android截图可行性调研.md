# Mac 连接 Android 手机一键截图：可行性调研

> 调研日期：2026-10-11 ｜ 本机：macOS 27.0（Apple Silicon，arm64）、Xcode 27
> 读者提示：先看「一、结论」即可；后面是细节和依据。标「未验证」的地方是没找到官方说法或没有真机实测。

---

## 一、结论（先说答案）

**能做，而且比 iPhone 还简单。**

- **怎么截**：Mac 上用谷歌官方的 `adb` 工具执行一条命令 `adb exec-out screencap -p`，手机会把当前屏幕拍成一张 **PNG 无损原图**，直接传回 Mac。之后的「存到下载文件夹 → 复制到剪贴板 → 用预览打开」和现在的 iPhone 版完全一样。
- **手机上要做什么**：打开「开发者选项」→ 打开「USB 调试」→ 第一次插线时在手机弹窗里点「允许」（建议勾选「始终允许」）。**手机上不用装任何 App，不用 root。**
- **Mac 上要做什么**：**不需要管理员密码（不用 sudo）**，不需要后台服务。这一点比现在的 iPhone 方案（要输密码装隧道服务）省事。
- **推荐方案**：菜单栏 App 里内置一份 `adb`，有线（USB）为主；无线调试作为进阶选项。不推荐 scrcpy（它是做实时投屏的，截一张图用它是大炮打蚊子）。
- **主要的坑**：
  1. **银行、支付、部分视频 App 的页面截出来是黑的**（App 自己禁止截图，这是安卓的安全机制，绕不过去，也不该绕）。
  2. **华为新系统（HarmonyOS NEXT / 鸿蒙 5 及以后的「纯血鸿蒙」）不支持 adb**，要换用华为的 `hdc` 工具，相当于再写一套适配。老的鸿蒙 2/3/4（基于安卓）仍然用 adb。
  3. **三星**手机若开了「自动拦截器（Auto Blocker）」里的「阻止通过 USB 线发出的命令」，adb 会连不上，需要用户关掉这个开关。
  4. **授权会过期**：安卓 11+ 默认 7 天没用就收回电脑的调试授权，需要重新点「允许」（开发者选项里可以关掉这个超时）。
  5. 无线调试每次重连端口会变、换 Wi-Fi 要重新配对；Mac 上 App 第一次走无线会弹「本地网络」权限窗。
  6. 打包 adb 进 App 有一点许可证上的灰色（谷歌 SDK 许可写了不可再分发），但 adb 本身是 Apache 2.0 开源，且 scrcpy 等知名开源项目就是直接打包官方 adb 发布的。属于非法律意见，见第五节。

---

## 二、技术路线对比

| 路线 | 原理（通俗版） | 速度（经验估计，未实测） | 画质 | 手机端装 App？ | 推荐度 |
|---|---|---|---|---|---|
| **A. `adb exec-out screencap -p`** | adb 让手机执行系统自带的截图命令，PNG 数据直接从数据线流回 Mac，手机上不留文件 | 约 0.5～2 秒（主要耗在手机端压缩 PNG） | PNG 无损 | 否 | ★★★★★ 首选 |
| B. `adb exec-out screencap`（不加 `-p`） | 手机吐出未压缩的原始像素，Mac 端自己编码成 PNG/JPEG | 可能更快（省掉手机端压缩），但传输量大（一张约 10MB 级） | 无损 | 否 | ★★★★ 优化选项 |
| C. `adb shell screencap /sdcard/x.png` + `adb pull` + 删除 | 先存到手机里，再拷回来，再删掉 | 比 A 慢（多两次往返），且会在手机上写临时文件 | PNG 无损 | 否 | ★★ 仅兜底 |
| D. scrcpy | 往手机推一个临时服务程序，把屏幕编码成 **H.264 视频流** 传给电脑实时显示 | 启动要 1～2 秒，之后可以实时看 | 视频帧，**有损** | 否（临时推送，退出即清理） | ★★ 做"实时预览"才值得 |
| E. 手机上点系统截图 + Mac 拉取最新文件（MTP/adb pull） | 用户在手机上自己截，Mac 只负责把相册里的最新截图拿过来 | 取决于用户 | 原图 | 否 | ★ 不是"一键" |
| F. 手机上装配套 App（MediaProjection 录屏接口）通过 Wi-Fi 发给 Mac | 自己写安卓 App | — | 可无损 | **是** | ★ 工作量大，且安卓每次录屏都要用户确认 |

### 各路线细节

**A/B/C：screencap（推荐）**
- `screencap` 是安卓系统内置命令，官方文档原文示例：`adb shell screencap /sdcard/screen.png`，并提到"用 `exec-out` 代替 `shell` 来拿原始数据"：`adb exec-out screencap -p > screen.png`。
  来源：https://developer.android.com/tools/adb
- 为什么用 `exec-out` 不用 `shell`：`shell` 在部分老设备上会经过伪终端，把二进制里的换行符改掉，导致 PNG 损坏；`exec-out` 是原样传输。（老设备换行问题为业界常识，未在官方页找到原文——未验证具体受影响版本。）
- `screencap` 源码里的参数（AOSP main 分支）：`-p` 输出 PNG；`-d <display-id>` 指定屏幕（折叠屏/多屏）；`-a` 截所有屏幕；不加 `-p` 且不给文件名时输出原始像素（头部是宽、高、像素格式、色彩空间四个 32 位整数，后面是像素）。代码里还接受 `-j`（JPEG），但帮助文本没写，**哪个安卓版本开始支持 `-j` 未验证**，不建议依赖。
  来源：https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/cmds/screencap/screencap.cpp
- 截图权限：`screencap` 以 adb 的 shell 身份运行，这个身份本来就有截屏权限，**不需要 root**。

**D：scrcpy**
- 开源（Apache-2.0），最新版 v5.0.1（2026-10-08 发布），支持 Android 5.0+，不需要 root，"手机上不会留下任何安装"。
- 原理：电脑先 `adb push` 一个 `scrcpy-server` 到手机 `/data/local/tmp`，再用 `app_process` 以 shell 身份运行，用 MediaCodec 把屏幕编码成 H.264 视频流。
- 没有内置"截一张图"功能（只有录像）；从视频流里抠一帧是有损的。所以**单纯截图不选它**；以后要做"Mac 上实时看手机画面再点截图"才考虑。
  来源：https://github.com/Genymobile/scrcpy 、https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md

**E：为什么 MTP 不行**
- MTP（插线时选"传输文件"那个模式）是**纯文件传输协议**，只能浏览/拷贝手机里已有的照片和文件，**没有"让手机截屏"这种指令**。所以它最多只能做到"你在手机上按截图键，Mac 自动把最新截图拿过来"，不是一键截图。
- 另外 macOS 本身不自带 MTP 支持（需要第三方库，如 libmtp），开发成本不低，收益又小。

---

## 三、手机端前提条件

### 3.1 通用步骤（所有安卓手机）
1. **打开开发者选项**：设置 → 关于手机 →（软件信息）→ 连续点「版本号 / Build number」7 次，提示"您已处于开发者模式"。
   不同品牌位置不同（如三星在「关于手机 → 软件信息 → 版本号」；小米在「我的设备 → 全部参数 → OS 版本」，小米路径为常见经验，未在官方页核实）。
   来源：https://developer.android.com/studio/debug/dev-options
2. **打开 USB 调试**：设置 → 系统 →（高级）→ 开发者选项 → USB 调试。
3. **授权这台 Mac**：插线后手机弹出「允许 USB 调试吗？」并显示电脑的 RSA 密钥指纹，点「允许」，**建议勾选「始终允许使用这台计算机进行调试」**。安卓 4.2.2+ 都有这个弹窗。
   - 授权前 `adb devices` 会显示 `unauthorized`，App 要提示用户"请看手机并点允许"。
   - Mac 端的密钥默认在 `~/.android/adbkey`（与 Android Studio 共用；这一路径为 adb 惯例，官方页未写明）。
   - **授权超时**：安卓 11 起，长时间（默认 7 天）没用过的电脑授权会被自动收回；开发者选项里有「停用 adb 授权超时功能」可关闭。（来源为 AOSP 设置代码和第三方文章，菜单名称各厂商可能不同——部分未验证）
   来源：https://developer.android.com/tools/adb

### 3.2 无线调试（Android 11+）
- 手机和 Mac 必须在**同一个 Wi-Fi**。
- 手机：开发者选项 → 无线调试 → 打开 →「使用配对码配对设备」，屏幕会显示 IP、端口、6 位配对码。
- Mac：`adb pair IP:配对端口` 输入配对码（**只需配对一次**）；之后 `adb connect IP:连接端口`，或者靠 mDNS 自动发现自动连接（`adb mdns services` 可查看）。
- 注意：配对端口和连接端口是两个不同的端口，且**连接端口每次重开无线调试都会变**，所以 App 最好用 mDNS 自动发现，而不是让用户记 IP。
- Android 10 及以下：只能先插线执行 `adb tcpip 5555`，再 `adb connect IP:5555`，手机重启后失效。
- 实际体验：无线比有线慢、偶尔断，手机息屏久了或换网络后可能需要重新打开无线调试。
  来源：https://developer.android.com/tools/adb （Connect to a device over Wi-Fi 一节）

### 3.3 各厂商额外限制

| 品牌 | 情况 | 对截图的影响 | 可信度 |
|---|---|---|---|
| **小米 / 红米（MIUI / HyperOS）** | 除「USB 调试」外还有「USB 调试（安全设置）」开关，打开它通常要登录小米账号 | **纯截图不需要**它；它管的是"模拟点击/授予权限"（scrcpy 控制手机时才需要，并需重启） | scrcpy 文档已证实其用途；"截图不需要"为推断，未真机验证 |
| **华为 / 荣耀（EMUI、HarmonyOS 2/3/4）** | 底层是安卓，照常用 adb；可能需要在弹窗/设置里"仅充电模式下允许 ADB 调试" | 照常可用 | 未验证具体菜单 |
| **华为 HarmonyOS NEXT（鸿蒙 5+，纯血鸿蒙）** | **不再支持 adb**，改用华为的 `hdc`（OpenHarmony Device Connector）。开启方式类似：设置 → 系统 → 开发者选项 → USB 调试 / 无线调试，首次连接弹「信任」 | 需要另写一套 hdc 适配，见 3.4 | hdc 文档已证实；"不支持 adb"来自多家媒体报道 |
| **三星（One UI 6+）** | 「自动拦截器 Auto Blocker」开启后，其中「阻止通过 USB 线发出的命令」会拦掉 adb | 需让用户在 设置 → 安全和隐私 → 自动拦截器 里关掉该项 | 三星官方支持页已证实 |
| **OPPO / 一加（ColorOS）、vivo / iQOO（OriginOS）** | 常见限制集中在"通过 USB 安装应用""模拟点击"需额外开关或登录账号；部分版本会在一段时间不用后自动关闭开发者选项/USB 调试 | 纯截图一般只需 USB 调试；"自动关闭"会导致过几天突然连不上 | **未验证**（没找到官方文档，需真机测试） |

### 3.4 HarmonyOS NEXT 的 hdc 方案（概要）
- 连接与选设备：`hdc list targets -v` 列设备，`hdc -t <设备号> ...` 指定设备，无线用 `hdc tconn IP:端口`，拷文件用 `hdc file recv <手机路径> <本地路径>`。
  来源：OpenHarmony 官方文档 https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/dfx/hdc.md
- 截图命令：`hdc shell snapshot_display -f /data/local/tmp/xxx.jpeg`（或 `.png`），再 `hdc file recv` 取回。**这个命令未在华为官方文档中找到**，来自开发者文章和 OpenHarmony smartperf 源码；输出格式是否由扩展名决定、是否支持 PNG 无损——**未验证**。
  参考：https://dev.to/abnerming888/harmonyos-development-screen-caption-and-screen-recording-functions-in-deveco-studio-2gk2 、https://gitcode.com/openharmony-sig/smartperf/blob/master/device/device_command/Capture.cpp
- hdc 获取：随 DevEco Studio 或华为 Command Line Tools 提供（`sdk/default/openharmony/toolchains/hdc`），有 macOS 版本。**能否随 App 再分发：未验证**。
- 建议：第一版先不做纯血鸿蒙，作为后续扩展。

---

## 四、特殊情况

### 4.1 FLAG_SECURE：银行 / 支付 / 部分视频 App 截图是黑屏
- 安卓 App 可以给窗口加 `FLAG_SECURE` 标记，官方说明：该标记让系统**不允许截图、不在非安全显示器（如投屏）上显示**，截图结果是空白。银行、密码管理器、支付页、部分视频平台都会用。
  来源：https://developer.android.com/security/fraud-prevention/activities 、https://developer.android.com/reference/android/view/WindowManager.LayoutParams#FLAG_SECURE
- `adb screencap` 也受此限制（多方报告为黑屏，官方未单独写明 adb 行为——**未在真机验证**，但业界普遍如此）。scrcpy 投屏同样是黑的。
- 这是安全设计，**App 不应尝试绕过**（需要 root 才可能，也违背用户和 App 方意愿）。
- 产品处理：截图后检测图片是否几乎全黑，若是就提示"当前页面禁止截图（银行/支付类 App 的安全保护）"，避免用户以为工具坏了。

### 4.2 锁屏 / 息屏
- 锁屏时截到的就是锁屏画面（screencap 截的是"当前显示的内容"）。
- 屏幕关闭时可能得到全黑图或报错（**未验证**，不同机型可能不同）。可选做法：截图前执行 `adb shell input keyevent KEYCODE_WAKEUP` 点亮屏幕——但这算"操作手机"，建议做成可选项、默认关闭。
- 首次授权必须在手机解锁状态下点「允许」。

### 4.3 多台设备同时连接
- 多设备时不指定目标，adb 会报错 `more than one device/emulator`。
- 选择方式：`adb -s <序列号>`（最常用）、环境变量 `ANDROID_SERIAL`、`-d`（唯一的 USB 设备）、`-e`（唯一的模拟器）。
- `adb devices -l` 会列出序列号、`usb:` 端口、`model:` 型号等，App 菜单里可以据此显示"Pixel 8（USB）/ Xiaomi 14（Wi-Fi）"让用户选，并记住上次选择。
- 无线连接的设备序列号形如 `192.168.1.5:41234` 或 `adb-XXXX._adb-tls-connect._tcp`。
  来源：https://developer.android.com/tools/adb

### 4.4 折叠屏 / 多屏
- 默认截第一块物理屏；需要时用 `screencap -d <display-id>` 指定（屏幕 ID 可通过 `adb shell dumpsys SurfaceFlinger --display-id` 查询——命令为经验做法，未验证各版本兼容性）。

---

## 五、Mac 端问题

### 5.1 要不要管理员权限 / root？
- **不需要。** adb 以普通用户身份运行，通过 USB 直接和手机通信；它会在本机 `127.0.0.1:5037` 起一个后台服务（第一次运行任何 adb 命令时自动启动）。
- 对比：现有 iPhone 方案需要 `sudo` 安装一个以 root 运行的隧道服务（LaunchDaemon），这是 iOS 17+ 开发者服务的要求。

### 5.2 会不会触发 macOS 隐私权限弹窗（TCC）？
| 场景 | 是否弹窗 | 说明 |
|---|---|---|
| USB 有线 | 一般不弹 TCC | macOS 没有"USB 设备"隐私权限。但 Apple Silicon Mac（macOS 13+）对**新接入的 USB 配件**可能弹「允许配件连接？」，这是系统层面的，iPhone 也一样（与系统"安全性"设置有关，未逐项验证）。 |
| 与本机 adb 服务通信（127.0.0.1:5037） | 不弹 | 回环地址不属于"本地网络"。 |
| **无线调试** | **会弹「本地网络」权限** | macOS 15 起，App 连接局域网 IP、做 Bonjour/mDNS 发现都需要「本地网络」权限。苹果文档明确：**App 启动的辅助工具（比如内置的 adb）访问局域网时，系统把这笔账算在 App 头上**，弹窗显示 App 的名字，用户允许后对整个 App 生效。 |

- 要做的事：在 App 的 `Info.plist` 加 `NSLocalNetworkUsageDescription`（说明文字，如"用于通过 Wi-Fi 连接安卓手机截图"）；若 App 自己做 Bonjour 发现，还要在 `NSBonjourServices` 里列出 `_adb-tls-connect._tcp`、`_adb-tls-pairing._tcp`（服务名来自 adb 帮助输出 `ADB_MDNS_AUTO_CONNECT` 默认值 `adb-tls-connect`；pairing 服务名为推断，未验证）。
- 坑：权限是按**代码签名身份**记的，所以 App 必须用正式 Developer ID 签名，否则可能反复弹窗。从终端运行的命令行工具不受此限制，所以"终端里能连、App 里连不上"是典型现象。
- 未验证点：adb 后台服务是"分叉后脱离"的守护进程，是否仍被系统归属到我们的 App——按苹果"负责代码"规则应当是，但**未实测**。另外如果用户的 adb 服务是此前从终端/Android Studio 启动的，那它不归我们的 App 管，也就不会弹窗。
  来源：https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy

### 5.3 在 App 里内置 adb：体积、签名公证、许可

**本机实测情况（只读检查）**
- `which adb`：不在 PATH 里；但 `~/Library/Android/sdk/platform-tools/adb` 存在（随 Android Studio 安装），版本 `37.0.0-14910828`。
- 文件是 **通用二进制（x86_64 + arm64）**，约 **20 MB**；只保留 arm64 约 **9.7 MB**（`lipo -thin` 实测）。仅依赖系统库（libSystem、CoreFoundation、IOKit、Security 等），**不依赖额外 dylib**，单文件就能跑。
- 已由 **"Developer ID Application: Google LLC (EQHXZ8M8AV)"** 签名，开启了 Hardened Runtime。
- 当前没有手机连接：`adb devices -l` 输出为空列表。

**打包做法**
- 放到 `YourApp.app/Contents/Helpers/adb`（或 `Contents/MacOS/`），用 `Process` 调用。
- 签名公证：App Store 外分发需要 Developer ID 签名 + 公证。最稳的做法是**用自己的 Developer ID 对 adb 重新签名（开 Hardened Runtime、带时间戳）**，再整体公证。保留谷歌原签名能否直接通过公证——**未验证**。
- 不需要 App 沙盒（App Store 外分发）。若将来要上 Mac App Store，沙盒内启动外部二进制、访问 USB 都很麻烦，基本不现实。

**许可（非法律意见）**
- 谷歌 platform-tools 下载包附带的是《Android SDK 许可协议》，其中 3.4 条写了"不得再分发"；但 3.5 条又说，SDK 中以开源许可发布的组件以开源许可为准。adb 源码在 AOSP 中是 **Apache 2.0**。
- 先例：**scrcpy 的 macOS 官方发布包直接打包了谷歌的官方 adb**（其构建脚本从 `dl.google.com` 下载 platform-tools r37.0.1 并只取出 `adb`）。Windows 版历来也打包 adb。
  来源：https://github.com/Genymobile/scrcpy/blob/master/app/deps/adb_macos.sh
- 稳妥选项（按成本从低到高）：
  1. 不内置，引导用户 `brew install --cask android-platform-tools`，或自动探测 `~/Library/Android/sdk/platform-tools/adb`（适合开发者用户，不适合小白）。
  2. 内置官方 adb 并附上 `NOTICE` 许可文本（参照 scrcpy 做法）。
  3. 从 AOSP 源码自行编译 adb（纯 Apache 2.0，最干净，但编译 AOSP 工具链工作量大）。
  4. 用 Swift 自己实现 adb 协议（USB 通信 + RSA 认证），彻底不依赖 adb；工作量最大，不建议第一版做。

**另一个坑：adb 版本冲突**
- 同一台 Mac 上只能有一个 adb 服务占着 5037 端口。如果用户另装了 Android Studio，两个不同版本的 adb 会互相"踢掉"对方的服务（提示 `adb server version doesn't match this client; killing...`），导致 Android Studio 的调试或我们的截图偶尔断开。
- 对策：优先使用用户已安装的 adb（若版本够新）；否则用内置的。或者 App 直接通过 TCP 跟已运行的 adb 服务说话（adb 服务协议是公开的文本协议），不额外启动进程。

---

## 六、与 iOS 方案对比

| 对比项 | iOS（现有脚本：pymobiledevice3） | Android（adb screencap） |
|---|---|---|
| 手机端前置条件 | 信任此电脑 + **开发者模式**（需重启手机）+ 挂载开发者磁盘镜像（重启后要重新挂） | 开发者选项 + **USB 调试** + 点「允许」授权 |
| Mac 是否需要 root / 管理员密码 | **需要**（sudo 安装 root 运行的隧道服务） | **不需要** |
| 后台常驻服务 | 需要（隧道 LaunchDaemon） | adb 服务按需自动启动，不需要安装 |
| 是否需要"开发者模式" | 是（iOS 16+ 开发者模式） | 是（开发者选项 + USB 调试，不需重启） |
| 手机端装 App | 否 | 否 |
| 无线支持 | 理论上可通过 Wi-Fi 隧道，现有脚本未做（未验证） | 安卓 11+ 官方支持无线调试（需同一 Wi-Fi、首次配对） |
| 画质 | PNG 无损（脚本再转 JPEG） | PNG 无损 |
| 速度（未实测） | 约 1～2 秒（含隧道就绪等待） | 约 0.5～2 秒 |
| 截不到的情况 | 系统保护内容（如 DRM 视频）可能为黑（未验证） | FLAG_SECURE 页面为黑屏 |
| 授权会过期吗 | 信任关系较持久；手机重启后需重挂开发者镜像 | 安卓 11+ 默认 7 天不用即过期（可关） |
| Mac 端依赖 | Python + pymobiledevice3（打包进 App 较麻烦） | 单个 adb 文件（约 10 MB，打包简单） |
| 实现难度 | 中偏高 | **低** |
| 厂商差异 | 无（只有苹果） | 有（小米/三星/华为鸿蒙 NEXT 等） |

---

## 七、同一个 Mac App 同时支持 iOS + Android 的架构建议

### 7.1 核心思路：统一的「设备提供者」接口
把"怎么从手机拿到一张图"抽象出来，后面的"保存/复制/打开/通知/快捷键"全部共用。

```swift
struct PhoneDevice: Hashable {
    let id: String            // iOS: UDID；Android: adb 序列号；鸿蒙: hdc connect-key
    let name: String          // "iPhone 16 Pro" / "Pixel 8"
    let platform: Platform    // .iOS / .android / .harmony
    let transport: Transport  // .usb / .wifi
    let state: State          // .ready / .unauthorized / .needsDeveloperMode / .offline
}

protocol DeviceProvider {
    var platform: Platform { get }
    func listDevices() async throws -> [PhoneDevice]
    func screenshot(_ device: PhoneDevice) async throws -> Data   // 统一返回 PNG 数据
    func diagnose(_ device: PhoneDevice) async -> [SetupHint]     // "请在手机上点允许" 等引导
}

// 实现
final class IOSProvider: DeviceProvider { ... }        // pymobiledevice3 / 后续可换原生实现
final class AndroidADBProvider: DeviceProvider { ... } // adb exec-out screencap -p
final class HarmonyHDCProvider: DeviceProvider { ... } // 以后再做：hdc snapshot_display
```

```
快捷键 ⌘⇧X / ⌥⌘⇧X
        │
  DeviceManager（汇总所有 Provider 的设备列表、记住"当前设备"）
        │  screenshot() → PNG Data
  ShotPipeline（共用）：黑屏检测 → PNG 原图 或 转 JPEG → 存 ~/Downloads → 复制剪贴板 → 预览打开 → 通知
```

### 7.2 关键设计点
1. **设备选择**：只有一台设备时直接截；多台时菜单栏里列出（带 iOS/安卓图标、USB/Wi-Fi 标记），记住上次选择。
2. **状态引导**（对非开发者最重要）：把 adb 的 `unauthorized`、`offline`、找不到设备等状态翻译成人话，例如"请解锁手机并在弹窗中点「允许」"、"请打开开发者选项里的 USB 调试（点这里看图文教程）"、"三星手机请关闭自动拦截器中的 USB 命令拦截"。
3. **adb 管理**：内置 adb 放 `Contents/Helpers/`；启动时先探测用户已有的 adb，避免版本互踢；截图走 `adb -s <serial> exec-out screencap -p`，设超时（如 10 秒）。
4. **设备发现**：定时执行 `adb devices -l`（或 `adb track-devices` 持续监听），无需轮询太频繁。
5. **黑屏检测**：截完检查是否接近全黑，是则提示 FLAG_SECURE，而不是静默保存一张黑图。
6. **无线调试作为进阶**：在设置页做"配对安卓手机（Wi-Fi）"向导，引导用户输入手机上显示的配对码，内部调用 `adb pair`；第一次会弹 macOS「本地网络」权限。
7. **鸿蒙 NEXT 预留**：接口已支持，第二阶段再加 `HarmonyHDCProvider`（需先确认 hdc 可否再分发、snapshot_display 是否稳定）。

### 7.3 建议的落地顺序
1. **第一阶段**：AndroidADBProvider（USB 有线）+ 共用截图流水线 + 状态引导。工作量小、收益大。
2. **第二阶段**：Android 无线调试配对向导；iOS 部分去掉 sudo 依赖的可行性研究（另题）。
3. **第三阶段**：HarmonyOS NEXT（hdc）、可选的实时预览（scrcpy 思路）。

---

## 八、未验证 / 需真机测试的点清单

- [ ] 截图速度（各机型 `exec-out screencap -p` 实际耗时；原始像素模式是否更快）
- [ ] `adb screencap` 在 FLAG_SECURE 页面确为黑屏（各厂商 ROM）
- [ ] 息屏状态下 screencap 的结果
- [ ] 小米「USB 调试（安全设置）」对截图是否确实无影响
- [ ] OPPO / vivo 是否会自动关闭 USB 调试、是否有额外开关
- [ ] 老款华为 / 荣耀"仅充电模式下允许 ADB 调试"的具体位置
- [ ] HarmonyOS NEXT 上 `snapshot_display` 的参数、输出格式、是否无损；hdc 能否随 App 分发
- [ ] `screencap -j`（JPEG）从哪个安卓版本开始支持
- [ ] 内置 adb 保留谷歌签名能否直接通过公证（还是必须重签）
- [ ] App 启动的 adb 守护进程在无线调试时，「本地网络」权限是否正确归属到 App；`_adb-tls-pairing._tcp` 服务名
- [ ] Apple Silicon「允许配件连接」弹窗对安卓手机的实际表现

---

## 参考来源
- Android 官方 adb 文档：https://developer.android.com/tools/adb
- 开发者选项与 USB 调试：https://developer.android.com/studio/debug/dev-options
- FLAG_SECURE 与敏感页面：https://developer.android.com/security/fraud-prevention/activities ；https://developer.android.com/reference/android/view/WindowManager.LayoutParams#FLAG_SECURE
- screencap 源码（AOSP）：https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/cmds/screencap/screencap.cpp
- scrcpy：https://github.com/Genymobile/scrcpy ；原理 https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md ；macOS https://github.com/Genymobile/scrcpy/blob/master/doc/macos.md ；FAQ https://github.com/Genymobile/scrcpy/blob/master/FAQ.md ；内置 adb 脚本 https://github.com/Genymobile/scrcpy/blob/master/app/deps/adb_macos.sh
- Apple TN3179 本地网络隐私：https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- OpenHarmony hdc 文档：https://gitee.com/openharmony/docs/blob/master/zh-cn/application-dev/dfx/hdc.md
- HarmonyOS NEXT 弃用 adb 报道：https://promon.io/security-news/harmonyos-next ；https://www.xatakandroid.com/sistema-operativo/harmonyos-next-no-oficial-europa-he-probado-hice-mi-primera-aplicacion
- snapshot_display 用法（第三方）：https://dev.to/abnerming888/harmonyos-development-screen-caption-and-screen-recording-functions-in-deveco-studio-2gk2 ；https://gitcode.com/openharmony-sig/smartperf/blob/master/device/device_command/Capture.cpp
- 三星自动拦截器：https://www.samsung.com/uk/support/mobile-devices/protect-your-galaxy-device-with-the-new-auto-blocker-feature/
- adb 授权超时（AOSP 设置代码镜像）：https://git.replicant.us/replicant-next/packages_apps_Settings/tree/src/com/android/settings/development/AdbAuthorizationTimeoutPreferenceController.java

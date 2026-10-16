# Mac 是怎么"看到"iPhone 屏幕的？——一篇写给非开发者的连接与截图科普

> 适合读者：产品经理、设计师、测试同学等**零 iOS 开发基础**的朋友。
> 背景：本文以本项目的 `install_iphone_shot.sh`（一键安装"按快捷键截 iPhone 真机屏幕"的工具）为线索，把"Mac 和 iPhone 之间到底发生了什么"讲清楚。
> 写作环境：macOS 27.0、Xcode 27.0、pymobiledevice3 11.26.0，测试手机 iPhone 16 Pro（iOS 26.6.2）。
> 标注约定：**【已核实】**＝在本机运行命令或读源码确认过；**【公开资料】**＝来自苹果文档/开源社区的通行说法；**【推测/未验证】**＝合理推断，但没有亲手验证。

---

## 0. 一句话版本

你按下 ⌘⇧X 后，Mac 先通过**数据线或 Wi‑Fi**找到手机，凭着之前"信任此电脑"时交换过的**钥匙**证明自己身份，再在两者之间搭一条加密的**专用隧道**，通过隧道敲开手机上一个只对开发者开放的**截图服务**的门，拿回一张 PNG，最后在 Mac 上压缩成 JPEG 放进剪贴板。

而它之所以"有时灵、有时不灵"，基本都卡在三道门槛上：**有没有连上**、**开发者模式开没开**、**开发者磁盘镜像挂没挂**。

---

## 1. 全景图：从按快捷键到剪贴板

先看全貌，后面每一节再展开其中一个格子。

```
 你按下 ⌘⇧X
     │
     ▼
┌──────────────────── Mac ────────────────────────────────────────────┐
│ 「快捷指令」App ──运行──▶ ~/.iphone-shot/shot.sh                    │
│                              │                                       │
│        ① 问后台隧道服务：手机在吗？                                  │
│           curl http://127.0.0.1:49151/   (tunneld 的"前台接待")      │
│                              │                                       │
│        ② pymobiledevice3 developer dvt screenshot --tunnel ''        │
│                              │                                       │
│   ┌──────────────────────────┴─────────────────────────────┐        │
│   │ tunneld（root 后台常驻，LaunchDaemon 开机自启）          │        │
│   │   └─ 维护一条加密隧道 + 一块虚拟网卡 utunN               │        │
│   └──────────────────────────┬─────────────────────────────┘        │
│                              │ 隧道里的流量最终交给…                │
│   usbmuxd（苹果自带"总机"，/var/run/usbmuxd）                        │
└──────────────────────────────┼──────────────────────────────────────┘
                               │  USB 数据线  或  同一 Wi‑Fi 局域网
┌──────────────────────────────┼──────────────── iPhone ───────────────┐
│   lockdownd（门卫，端口 62078）── 核对配对记录（"钥匙"）             │
│        │                                                            │
│        ├─ CoreDeviceProxy 服务 ──▶ 隧道的手机端                      │
│        │                                                            │
│   RSD 服务目录（隧道里的"服务黄页"）                                 │
│        └─ com.apple.instruments.dtservicehub（DVT 开发者服务）       │
│              └─ screenshot 通道 ──▶ 抓一帧屏幕，返回 PNG             │
│                 ↑ 前提：开发者模式已开 + 开发者磁盘镜像已挂载        │
└──────────────────────────────────────────────────────────────────────┘
                               │ PNG 回传
                               ▼
  Mac：sips 转 JPEG（质量 80）→ 存到 ~/Downloads → osascript 写入剪贴板 → open 预览
       （失败时：先 mounter auto-mount 挂载开发者镜像，再重试一次）
```

把这条链路想象成**寄快递**：
- 数据线 / Wi‑Fi ＝ 公路；
- usbmuxd ＝ Mac 这边的快递分拣中心；
- 配对记录 ＝ 双方签过的"长期合作协议"；
- lockdownd ＝ 手机小区门口的门卫；
- 隧道 ＝ 门卫批准后，专门给你开的一条带锁的专用通道；
- RSD ＝ 小区里的"商户黄页"，告诉你每个服务在几号门；
- DVT 截图服务 ＝ 只对持"开发者证"的人开放的照相馆，而且照相馆的设备（开发者磁盘镜像）每次停电（重启）后要重新搬进来。

---

## 2. 安装脚本逐步拆解：每一步在干什么、为什么

`install_iphone_shot.sh` 一共 4 步，加上它生成的 `shot.sh`。【已核实：逐行读过两个脚本，且 `~/.iphone-shot/shot.sh` 与安装脚本内嵌内容完全一致】

### 第 1 步：装 pymobiledevice3

```bash
python3 -m venv ~/.iphone-shot/venv
~/.iphone-shot/venv/bin/pip install --upgrade pymobiledevice3
```

- **python3**：macOS 本身不一定带，所以脚本让你没有时先跑 `xcode-select --install`（装"命令行开发工具"，里面带 python3）。
- **venv（虚拟环境）**：大白话就是"给这个工具单独准备一个工具箱"，装进去的东西不会和电脑里别的 Python 程序打架，删的时候把文件夹一删就干净。
- **pymobiledevice3**：一个开源的 Python 工具，作者通过研究苹果的通信协议，**用 Python 重新实现了 Mac 与 iPhone 对话的那一套**。苹果自己的官方工具藏在 Xcode 里（见第 9 节），pymobiledevice3 的好处是不依赖 Xcode、命令行友好、跨平台。

### 第 2 步：装一个"开机自启、root 权限"的后台隧道服务

```bash
sudo tee /Library/LaunchDaemons/com.iphoneshot.tunneld.plist ...
sudo launchctl bootstrap system /Library/LaunchDaemons/com.iphoneshot.tunneld.plist
```

- **LaunchDaemon**：macOS 的"系统级后台服务"。放进 `/Library/LaunchDaemons/` 的配置文件，会在**开机时（还没登录前）**由系统以 **root（超级管理员）** 身份启动。配置里的 `RunAtLoad`＝开机就跑，`KeepAlive`＝挂了自动拉起来。
- **它跑的是**：`pymobiledevice3 remote tunneld`。tunneld 是"隧道管家"：一直盯着有没有 iPhone 出现，一出现就自动和它建好隧道，并在 `127.0.0.1:49151` 开一个小小的 HTTP 接口，谁问它"现在有哪些手机、隧道地址是什么"，它就回答。
- **为什么要输入管理员密码**：一是往 `/Library/LaunchDaemons/` 写文件本身需要管理员权限；二是 tunneld 建隧道时要**在系统里新建一块虚拟网卡**（第 6 节细讲），这件事只有 root 能做。
- 日志写到 `/tmp/iphoneshot-tunneld.log`。

【已核实】本机该服务正在运行，日志里有一行 `Created tunnel --rsd fd5c:…::1 60685`，访问 `http://127.0.0.1:49151/` 返回：

```json
{"0000xxxx-…":[{"tunnel-address":"fd5c:930a:38d2::1","tunnel-port":60685,
  "interface":"usbmux-0000xxxx-…-Network", ...}]}
```

`ifconfig` 也能看到对应的虚拟网卡 `utun5`，地址 `fd5c:930a:38d2::2`、MTU 16000。也就是说：**手机没插线、只靠 Wi‑Fi，隧道也已经建好了**。

### 第 3 步：生成截图脚本 `shot.sh`

它做 5 件事：

| 步骤 | 命令 | 大白话 |
|---|---|---|
| 1. 等隧道就绪 | `curl 127.0.0.1:49151` 最多重试 10 秒 | 问隧道管家："手机到了吗？"刚插线时建隧道需要几秒 |
| 2. 截图 | `pymobiledevice3 developer dvt screenshot --tunnel '' 文件.png` | 通过 tunneld 提供的隧道，调用手机上的 DVT 截图服务。`--tunnel ''` 的意思是"用 tunneld 里的设备，只有一台就自动选它" |
| 3. 失败兜底 | `pymobiledevice3 mounter auto-mount` 后重试 | 失败最常见的原因是"开发者磁盘镜像"没挂（手机重启后会掉），自动挂上再试一次 |
| 4. 转格式 | `sips -s format jpeg -s formatOptions 80` | `sips` 是 macOS 自带的图片处理命令，把 PNG 压成质量 80 的 JPEG（传 `original` 参数则保留 PNG 原图） |
| 5. 进剪贴板 | `osascript -e 'set the clipboard to (read … as «class JPEG»)'` | 用 AppleScript 把图片放进剪贴板，然后 `open` 用"预览"打开 |

另外 `notify()` 用 `osascript display notification` 弹出系统通知告诉你失败原因。

### 第 4 步：检查开发者模式

```bash
pymobiledevice3 usbmux list                 # 能看到手机吗？
pymobiledevice3 amfi developer-mode-status  # 开发者模式开了吗？
pymobiledevice3 amfi reveal-developer-mode  # 没开：让"开发者模式"开关在手机设置里显示出来
pymobiledevice3 mounter auto-mount          # 开了：顺手挂上开发者镜像
```

【已核实】本机执行 `amfi developer-mode-status` 当前返回 `False`——这正是目前截图失败的原因。

### 最后：在「快捷指令」里绑快捷键

快捷指令 App 的"运行 Shell 脚本"动作需要先在设置里勾"允许运行脚本"，然后给两个快捷指令分别绑 ⌘⇧X（JPEG）和 ⌥⌘⇧X（PNG 原图）。

---

## 3. 物理层：数据线 vs Wi‑Fi，以及"总机"usbmuxd

### 3.1 两条路

- **USB 数据线**：最稳、最快。插线后 iPhone 其实会在 Mac 上"变出"一块 USB 网卡（专业名 CDC‑NCM，大白话："用数据线模拟一根网线"）。【公开资料】
- **Wi‑Fi**：Mac 和 iPhone 在**同一个局域网**里时，也能互相找到并通信，不用插线。

### 3.2 usbmuxd：Mac 上的"手机总机"

- **是什么**：macOS 自带的一个后台程序（本机进程路径 `/System/Library/PrivateFrameworks/MobileDevice.framework/.../usbmuxd`，以 `_usbmuxd` 用户运行）。它对外只开一个"总机号码"——本地套接字文件 `/var/run/usbmuxd`（权限 `srw-rw-rw-`，所有用户都能拨）。【已核实】
- **类比**：公司前台总机。Mac 上任何程序（Finder、Xcode、爱思助手、pymobiledevice3）想和手机说话，都不直接拉线，而是打给总机："帮我接 XX 手机的 62078 分机"。总机负责把通话转到 USB 或 Wi‑Fi 上，**多个程序可以同时和同一台手机说话**——"mux（多路复用）"就是这个意思。
- 它还负责**保管配对记录**（见第 4 节），别的程序要用钥匙时找它借（pymobiledevice3 源码里 `get_usbmux_pairing_record` 就是向 usbmuxd 借）。【已核实：读源码】

### 3.3 为什么没插线也能连？

【已核实】`pymobiledevice3 usbmux list` 当前输出里，用户手机的 `"ConnectionType": "Network"`，表示 usbmuxd 是通过网络而不是 USB 看到它的。

能做到这一点需要几个条件【公开资料】：
1. **以前用数据线连过、并点过"信任"**——Wi‑Fi 连接不能凭空建立信任，必须先有一份有线配对时留下的配对记录；
2. 通常还需要在 Finder 里对这台手机勾选过"在 Wi‑Fi 上时显示此 iPhone"（或 Xcode 里勾过"Connect via network"）；
3. 两台设备在**同一个局域网**，且网络允许它们互相"喊话"。

"喊话"的技术叫 **Bonjour**（苹果的局域网自动发现协议，大白话："在局域网里大喊一声'我在这儿'，同网的设备都能听到"，标准名 mDNS/DNS‑SD）。pymobiledevice3 源码里能看到 iPhone 在局域网里广播的几种"名片"：`_apple-mobdev2._tcp`（传统 Wi‑Fi 同步）、`_remotepairing._tcp`（新版配对隧道）、`_remoted._tcp`（USB 网卡上的新版服务）。【已核实：读 `bonjour.py`】

> 小提示：公司 Wi‑Fi、酒店 Wi‑Fi、开启了"客户端隔离"的路由器，往往会屏蔽这种喊话，这时 Wi‑Fi 连接就会失灵——插线最保险。

---

## 4. 信任与配对：「要信任此电脑吗？」背后发生了什么

第一次用数据线把 iPhone 连到 Mac，手机会弹出"要信任此电脑吗？"，点"信任"并输入锁屏密码。这一刻发生的事情可以类比成**两家公司签长期合作协议并互换公章**：【公开资料，配合源码印证】

1. Mac 生成一套自己的身份证书和密钥（"公章"），发给手机；
2. 手机确认是主人本人同意（所以要输锁屏密码），把 Mac 的公章收下，也把自己的证书给 Mac；
3. 双方各存一份**配对记录（pair record）**。以后再见面，出示公章、走一遍加密握手即可，不再弹窗。

**配对记录存在哪？**
- Mac 端：`/var/db/lockdown/` 目录，每台手机一个 `<UDID>.plist`。【已核实：pymobiledevice3 源码 `posix_util.py` 写明此路径；本机普通用户 `ls` 该目录得到 "Operation not permitted"，说明受系统保护】
- 普通程序拿不到这个目录，只能**通过 usbmuxd 去借**——这也是安全设计的一部分。
- iOS 17+ 新版"远程配对"（RemotePairing）还有另一套记录，pymobiledevice3 自己存在 `~/.pymobiledevice3/remote_*`。【已核实：读 `pair_records.py`】

**UDID 是什么**：每台苹果设备独一无二的编号，类似身份证号（本文一律打码成 `0000xxxx-…`）。

**常见现象**：
- 换了 Mac、重装系统、手机上"还原位置与隐私"后，配对记录对不上，就要重新插线点信任；
- 手机**锁屏状态**下，很多服务会拒绝工作，所以截图前最好先解锁手机。

---

## 5. lockdownd 与"服务"：手机上的门卫和一排按需开门的小店

### 5.1 lockdownd：门卫

iPhone 上有个系统程序叫 **lockdownd**，在 **62078 端口**等着（源码 `lockdown.py` 里 `SERVICE_PORT = 62078`）。【已核实：读源码】Mac 想做任何事，第一步都是：

1. 通过 usbmuxd 接通手机的 62078；
2. 出示配对记录，完成加密握手（证明"我是你信任过的那台电脑"）；
3. 说："请帮我启动 XX 服务"（协议里的 `StartService` 请求）；
4. lockdownd 临时开一个端口并告诉 Mac："XX 服务在 5xxxx 号门，去吧"。

### 5.2 服务：按需开门的小店

手机上的功能被拆成很多独立"服务"，**平时不开门，有人点名才启动**，用完就关。例子（名字来自源码/实测清单）：

| 服务名 | 干什么 |
|---|---|
| `com.apple.afc` | 读写手机上的部分文件（照片导入用到） |
| `com.apple.syslog_relay` | 实时读手机日志 |
| `com.apple.amfi.lockdown` | 查询/设置开发者模式 |
| `com.apple.mobile.mobile_image_mounter` | 挂载开发者磁盘镜像 |
| `com.apple.internal.devicecompute.CoreDeviceProxy` | iOS 17.4+ 用来建隧道 |
| `com.apple.mobile.screenshotr` | **老式**截图服务（需开发者镜像） |
| `com.apple.instruments.dtservicehub` | iOS 17+ 的 DVT 开发者服务总入口（含截图） |

这种设计的好处是：安全（每扇门单独授权）、省电（不用的不开）。

---

## 6. iOS 17 之后的大变化：隧道时代

### 6.1 发生了什么

从 iOS 17 起，苹果把**开发者相关的服务**搬到了一套新架构上：【公开资料 + 源码印证】

- **RemoteXPC**：苹果设备之间互相调用服务的新"通话协议"（XPC 是苹果系统内部程序之间打电话的方式，RemoteXPC 就是"跨设备打电话"版，底层用 HTTP/2）。
- **RSD（RemoteServiceDiscovery，远程服务发现）**：隧道里的一本"服务黄页"。连上 RSD，它会列出手机上所有可用服务各自在哪个端口。
- **CoreDevice**：Xcode 15 起苹果新的设备管理框架，Mac 上的 `devicectl` 命令就是它的前台（第 9 节）。
- **隧道（Tunnel）**：要访问 RSD 和开发者服务，必须先在 Mac 和 iPhone 之间建一条**加密的虚拟网络**——手机在这条虚拟网络里有一个 IPv6 地址（本机实测为 `fd5c:930a:38d2::1`），Mac 有另一个（`…::2`），然后像访问一台局域网服务器一样去访问手机的服务。

【已核实】在本机通过隧道连上 RSD（`remote rsd-info --tunnel ''`，耗时约 0.6 秒），黄页里一共列出了 **59 个服务**。值得注意的是，**里面没有** `com.apple.instruments.dtservicehub`，也没有 `com.apple.coredevice.screencaptureservice`——因为当前手机开发者模式关闭、开发者镜像没挂载，这些"开发者小店"根本没开张。（"挂载镜像后它们会出现"是通行说法，本次因不能改动手机状态而**未亲手验证**。）

### 6.2 为什么"隧道"传统上需要 root？

隧道要像一张真网卡一样工作，传统做法是让操作系统内核新建一块**虚拟网卡**（macOS 上叫 **utun**，大白话："系统里凭空插上一块看不见的网卡"），把加密隧道里收到的数据包交给内核网络栈处理。**新建网卡属于修改系统网络配置，只有 root 能做**。

源码注释还指出了第二个需要 root 的原因：走 USB 网卡那条老路时，需要**暂停 macOS 自带的 `remoted` 进程**（它会抢占手机的 RSD 连接），而暂停一个 root 进程也需要 root。【已核实：读 `remote/utils.py` 注释】

这就是本项目要装一个 root 权限 LaunchDaemon 的根本原因。

### 6.3 建隧道的三种方式对比

pymobiledevice3 11.x 提供三种建隧道的方式（加上第 4 种：苹果自己）：【已核实：读 `cli/cli_common.py`、`remote/userspace_tunnel.py`、`remote/native_tunnel.py`、`tunneld/server.py`】

| 方式 | 怎么用 | 原理（大白话） | 要 root 吗 | 优点 | 缺点 |
|---|---|---|---|---|---|
| **tunneld**（本项目在用） | 后台跑 `remote tunneld`，命令加 `--tunnel ''` | root 常驻管家，用**内核 utun 虚拟网卡**建隧道，一直保持 | **要** | 隧道常驻，每次截图不用重新握手，速度快；自动发现 USB / Wi‑Fi 设备 | 需要管理员密码、装系统级服务；卸载要手动清理 |
| **userspace（用户态）** | 命令加 `--userspace`（11.x 的默认方式） | 不让内核建网卡，而是**在程序内部用纯 Python 自己实现一套 TCP/IP 网络协议栈**（PyTCP），隧道在这个程序里自己"消化" | **不要** | 无需密码、无需装后台服务 | 每条命令都要重新建一次隧道（本机实测握手约 1 秒内）；Mac→手机的大文件传输（如上传开发者镜像）较慢；要求 iOS 17.4+（依赖 CoreDeviceProxy 服务） |
| **native（借苹果的）** | 命令加 `--native`（仅 macOS） | **蹭苹果自己的隧道**：问系统自带的 `remotepairingd` 要手机现成的隧道地址，再直接连上去 | **不要** | 不要 root、不要 Xcode，速度等同内核隧道 | 手机在这条隧道上只允许一个 RSD 连接，会和苹果自己的 `remoted` 互相"挤掉"，可能导致 Xcode/devicectl 短暂看不到手机，所以默认不启用 |
| （苹果官方）CoreDevice / devicectl | `xcrun devicectl …` | 苹果系统自己的 `remoted` + `remotepairingd` 负责隧道 | 不要（系统服务替你做了） | 官方、稳定 | 需要装 Xcode（体积大） |

【已核实】本机进程列表里能看到 `/usr/libexec/remoted`（root）、`remotepairingd`（当前用户）、`CoreDeviceService`（当前用户），说明苹果自己的这套设备管理服务在运行。

**tunneld 如何建隧道**（源码细节）：它同时开着几个"巡逻任务"——
- 盯 usbmuxd：一旦看到设备（不管 USB 还是 Network），就通过 lockdownd 启动 `CoreDeviceProxy` 服务，在其上建 TCP 隧道。本机日志里的任务名 `usbmux-…-Network` 说明**这次正是走 usbmuxd 的 Wi‑Fi 连接建起来的**；
- 盯 USB 网卡（`_remoted._tcp`）、盯 Wi‑Fi 上的 `_remotepairing._tcp` 和 `_apple-mobdev2._tcp`。

> 一个小坑【已核实：读源码 + `--help`】：本机 Python 是 3.9，tunneld 的默认协议显示为 QUIC；而源码提示 "iOS 18.2+ 已移除 QUIC 支持，TCP 需要 Python 3.13+"。不过走 usbmuxd/CoreDeviceProxy 这条路时源码**强制用 TCP**，不受影响——这也是本机 iOS 26 手机能正常建隧道的原因。纯 Wi‑Fi 的 RemotePairing 路线在 Python 3.9 上则可能失败（**推测**，未实测）。

### 6.4 那为什么不干脆用 userspace，省掉 root？

可以，而且是值得考虑的改进方向。取舍：
- 用 tunneld：一次输密码，之后每次截图最快；
- 用 `--userspace`：免密码、免后台服务，代价是每次截图多约 1 秒握手，且首次挂载开发者镜像（要往手机上传约 15 MB）会慢一些。

---

## 7. 开发者模式（Developer Mode）

### 7.1 是什么

iOS 16 起苹果加的一个**总开关**。关着的时候，手机拒绝一切"开发者级"操作：安装未上架的调试 App、调试、性能分析、以及——**通过开发者通道截图**。【公开资料】

**为什么截图算"开发者服务"？** 因为能远程抓屏、远程读进程、远程注入点击的能力一旦被滥用，等于把手机交给了别人。苹果的做法是：把这类能力打包进"开发者工具箱"（DVT / Instruments），默认上锁，必须**主人在手机上亲手打开开发者模式**才行。

### 7.2 怎么开

1. 手机：**设置 → 隐私与安全性 → 开发者模式**（滑到最底部"安全性"那一组）；
2. 打开开关，手机提示要**重启**；
3. 重启后解锁，会再弹一次"要打开开发者模式吗？"，点"打开"并输入锁屏密码。

**找不到这个开关？** 苹果默认把它藏起来，只有手机连过 Xcode 等开发工具后才会出现。安装脚本第 4 步的 `amfi reveal-developer-mode` 就是让它显示出来（AMFI 是 iOS 里负责"代码签名与开发者权限"的安全模块，大白话："手机里的安检员"）。

> 本机现状【已核实】：`amfi developer-mode-status` 返回 `False`，用户此前用 `devicectl` 截图时也报 "Developer mode is not enabled on device"。**这是当前截图失败的唯一已知原因**，按上面步骤打开即可。

---

## 8. 开发者磁盘镜像（DDI / Personalized DDI）

### 8.1 是什么

**DDI（Developer Disk Image，开发者磁盘镜像）**：一个十几 MB 的磁盘文件，里面装着手机上**开发者服务的程序本体**（包括 DVT 截图服务）。手机出厂并不带这些程序，用的时候由电脑"插"进去（**挂载 / mount**，大白话："像插 U 盘一样把一个磁盘接到手机系统上"）。

**类比**：照相馆的器材平时不放在小区里，需要时由电脑运过来摆好；一停电（重启），器材自动清场。

### 8.2 为什么手机重启后要重新挂载？

挂载是**临时**的，只存在于本次开机期间，重启即失效。【公开资料】这就是 `shot.sh` 里"失败就先 `mounter auto-mount` 再重试"的原因——它把"重启后要重新挂载"这件事自动化了。`auto-mount` 的帮助说明里也写明"已挂载时视为成功"，所以可以无脑调用。【已核实：`--help`】

### 8.3 为什么首次挂载需要联网？——"个性化"签名

- iOS 16 及以前：所有手机共用同一个按 iOS 版本区分的 DDI（Xcode 里按版本号放在 `DeviceSupport/` 目录），附带一个通用签名即可。
- **iOS 17 起：个性化 DDI（Personalized DDI）**。源码注释原文意思是"iOS 17.0 用每台设备个性化的镜像取代了共享镜像"。【已核实：`mobile_image_mounter.py`】

个性化的流程（大白话）：
1. Mac 问手机要一组**身份信息和一次性随机数（nonce）**；
2. Mac 把这些信息发给**苹果的签名服务器 TSS**（`gs.apple.com`，源码 `restore/tss.py` 有记录），请苹果出具一张"**只对这台手机、这次有效**"的许可单（签名票据）；
3. Mac 把镜像 + 许可单交给手机，手机验证苹果签名无误才挂载。

所以：**需要联网**（要找苹果签名）；苹果因此还能随时"收回许可"。源码显示，如果手机里已经存有之前的票据，会优先复用，就不必每次都联网。【已核实：读源码】

**镜像文件从哪来？**
- pymobiledevice3：从 GitHub 上的开源仓库 `doronz88/DeveloperDiskImage` 下载，缓存在 `~/.pymobiledevice3/Xcode_iOS_DDI_Personalized/`（本机已存在：`Image.dmg` 约 15 MB + `BuildManifest.plist` + `Image.trustcache`，下载于 10 月 10 日）。【已核实】
- Xcode：自带在 `/Library/Developer/DeveloperDiskImages/iOS_DDI/`。【已核实：目录存在】
- 补充【已核实：源码注释】：pymobiledevice3 对 iOS 27 起改用 "Cryptex" 形式安装 DDI（一种更新的系统组件封装格式）；本机 iOS 26.6.2 仍走 PersonalizedDMG 路线。

---

## 9. 三种截图通道，以及 devicectl 和 pymobiledevice3 的关系

### 9.1 手机上其实有三个"照相馆"

| 通道 | 服务名 | 年代 | 谁在用 |
|---|---|---|---|
| screenshotr | `com.apple.mobile.screenshotr` | 老式（走 lockdown） | pymobiledevice3 `developer screenshot`（已标记 Deprecated） |
| **DVT / Instruments** | `com.apple.instruments.dtservicehub` 里的 `com.apple.instruments.server.services.screenshot` 通道 | iOS 17+ 走 RSD 隧道 | **本项目**：`developer dvt screenshot` |
| CoreDevice 截图服务 | `com.apple.coredevice.screencaptureservice` | 新 | pymobiledevice3 `developer core-device screen-capture screenshot`；苹果 `devicectl` 很可能也是它（**推测**，基于命名与参数 `--display-unique-id` 一致） |

【已核实：均来自读源码】

**DVT / Instruments** 是什么：Instruments 是 Xcode 里的性能分析工具（看 CPU、内存、耗电等），DVT 是 Xcode 开发者工具的统称前缀。Instruments 在手机端有个"服务中心"，截图只是它提供的众多功能之一，走一种叫 **DTX** 的消息协议。

### 9.2 devicectl：苹果官方的"遥控器"

`xcrun devicectl` 是 Xcode 15+ 自带的官方命令行工具（`xcrun` 的意思是"去 Xcode 里找这个工具来运行"）。截图命令：

```bash
xcrun devicectl device capture screenshot --device <设备标识> --destination shot.png
```

【已核实：`xcrun devicectl help device capture screenshot`】帮助里写明只能存 `.png`、可用 `--display-unique-id` 指定屏幕。`xcrun devicectl list devices` 本机也能看到用户手机状态为 `available (paired)`。

### 9.3 两者关系

| | devicectl（官方） | pymobiledevice3（开源） |
|---|---|---|
| 来源 | 苹果，随 Xcode 发布 | 社区逆向苹果协议后用 Python 重写 |
| 依赖 | 需装 Xcode（几十 GB） | 只需 Python |
| 隧道 | 系统 `remoted` 自动负责 | 自己建（tunneld / userspace / native） |
| 稳定性 | 跟着 iOS 升级同步更新 | iOS 大版本后可能需等社区跟进 |
| 前提 | 一样：配对 + 开发者模式 + 开发者镜像 | 一样 |

**打个比方**：devicectl 是原厂遥控器；pymobiledevice3 是第三方万能遥控器，学会了原厂的红外编码。两者控制的是**同一台电视**，所以电视（手机）那边的限制（开发者模式、镜像）对两者一视同仁。

---

## 10. 另一条路：QuickTime 式"屏幕采集"（未实测）

你可能注意到：**macOS 自带的 QuickTime Player** 也能"新建影片录制 → 选择 iPhone"直接显示手机屏幕，而且**不需要开发者模式**。这走的是完全不同的通道：【公开资料，**本项目未实测**】

- 原理：iPhone 通过 USB 把自己伪装成一个"**摄像头/采集卡**"，Mac 用 **CoreMediaIO**（苹果的音视频采集框架）当作视频源来接收；需要程序先调用一个系统开关"允许屏幕采集设备"，手机才会以采集设备的身份出现。
- 特点：
  - 不需要开发者模式、不需要开发者镜像；
  - **只能有线**（Wi‑Fi 不行）；
  - Mac 程序需要**摄像头权限**（系统会弹窗）；
  - 得到的是**视频流**，截图要从中抓一帧，可能有压缩痕迹、分辨率/色彩与原生截图略有差异；
  - 采集时手机屏幕通常会被调整为录屏状态（如状态栏显示统一时间）——**推测，未验证**。
- 适用：如果团队里大多数人不愿意开开发者模式，可以作为备选方案研究。

---

## 11. Mac 端的权限与安全：为什么要密码，做成 App 会弹哪些窗

### 11.1 现在这个脚本

| 环节 | 权限 | 原因 |
|---|---|---|
| 安装 LaunchDaemon | 管理员密码（sudo） | 写 `/Library/LaunchDaemons/`、以 root 跑 tunneld |
| tunneld 建 utun 网卡 | root | 新建虚拟网卡属于系统网络配置 |
| 快捷指令运行脚本 | 在快捷指令设置里勾"允许运行脚本" | 默认禁止快捷指令执行 Shell |
| 保存到"下载"文件夹 | 可能首次弹"是否允许访问下载文件夹"（TCC） | macOS 隐私保护 |
| 通知 | 可能首次弹通知权限 | `osascript display notification` |

**TCC**（Transparency, Consent, and Control）：macOS 的隐私授权系统，大白话："系统设置 → 隐私与安全性"里那一排开关。

### 11.2 如果把它做成一个正经的 Mac App

【以下多为**推测/经验**，未做成 App 实测】

- **下载文件夹访问**（TCC）：首次写入 `~/Downloads` 时弹窗；
- **通知**：首次发通知时请求权限；
- **本地网络（Local Network）**：macOS 15 起，App 要在局域网里"喊话"（Bonjour 发现 Wi‑Fi 上的手机）会弹"允许查找本地网络上的设备吗？"；
- **管理员密码**：若仍沿用 tunneld 方案，需用 `SMAppService` 等机制安装特权帮手程序，会弹系统授权；改用 userspace / native 方式可以免掉；
- **Gatekeeper / 公证（Notarization）**：从网上下载的 App，必须用苹果开发者账号签名并提交苹果"公证"扫描，否则双击时提示"无法验证开发者"。Gatekeeper 就是 macOS 的"门口保安"，公证是"苹果预先查过没毒"的盖章；
- **为什么上不了 Mac App Store**：
  1. 商店 App 必须开**沙盒**（App 被关在小房间里），而访问 `/var/run/usbmuxd`、调用苹果私有的设备通信接口、安装 root 后台服务都与沙盒冲突；
  2. 使用私有框架/私有协议违反审核规则；
  3. 内置 Python 运行时与第三方逆向协议也难以通过审核。
  所以这类工具基本只能**官网下载 + 签名公证**分发（同类工具如爱思助手 Mac 版、各种投屏工具也大多如此）。

---

## 12. 常见问题排查（FAQ）

**Q1：按快捷键后提示"没检测到 iPhone"。**
- 先看 tunneld 有没有隧道：浏览器打开 `http://127.0.0.1:49151/`，返回 `{}` 说明没设备；
- 插上数据线、**解锁手机**，第一次连这台 Mac 时点"信任"；
- 只靠 Wi‑Fi 时：确认两者在同一 Wi‑Fi、路由器没开客户端隔离；不行就插线；
- 看日志：`/tmp/iphoneshot-tunneld.log`。

**Q2：检测到了，但"截图失败"。**
按概率排序：
1. **开发者模式没开**（本机当前就是这种情况）→ 见第 7 节；
2. **开发者镜像没挂**（手机重启过）→ 脚本会自动挂，但**首次挂载需要 Mac 能访问 GitHub（下载镜像）和苹果 `gs.apple.com`（签名）**，公司网络/代理拦截会失败；
3. 手机锁屏 → 解锁再试；
4. 详情看 `/tmp/iphoneshot.log`。

**Q3：手机重启后就不灵了，再按一次又好了？**
正常现象。重启清空了开发者镜像，第一次截图触发了自动挂载（需几秒），第二次就快了。

**Q4：同时有好几台手机在网（同事的手机也在同一 Wi‑Fi）怎么办？**
- `--tunnel ''` 表示"没指定就自动选/让你选"。只有一台时自动选；**多台时会进入交互式选择**，而快捷指令里没人能回答，所以会卡住或失败（**推测**，基于源码 `prompt_device_list` 逻辑，未实测多机场景）；
- 改法：在 `shot.sh` 里写死自己手机的 UDID：`--tunnel 你的UDID`；
- 另：只有**和这台 Mac 配对过**的手机才会被连上，陌生人的手机不会被误连。`devicectl list devices` 里看到的"unavailable"设备，是历史上连过但现在不在线的。

**Q5：要不要一直开着开发者模式？有风险吗？**
开发者模式本身只是"允许开发者工具工作"，被利用的前提仍是对方拥有你信任过的电脑（配对记录）。日常风险较低，但介意的话可以用完关掉（关掉后截图工具就失效）。

**Q6：怎么卸载？**
需要管理员权限：卸载 LaunchDaemon（`launchctl bootout` 后删除 plist），再删除 `~/.iphone-shot`、`~/.pymobiledevice3`。（本文只描述，不在此执行。）

**Q7：tunneld 日志里有 "NotOpenSSLWarning … LibreSSL 2.8.3" 警告？**
系统自带 Python 3.9 用的是旧版 LibreSSL，urllib3 发出的提示。【已核实：每次运行都会出现】目前不影响截图，可忽略；长期建议改用较新 Python（3.13+ 还能解锁 tunneld 的 TCP 模式）。

---

## 13. 术语表

| 术语 | 大白话解释 |
|---|---|
| UDID | 每台苹果设备独一无二的编号，像身份证号 |
| usbmuxd | Mac 上的"手机总机"，所有程序通过它和手机说话，支持 USB 和 Wi‑Fi |
| `/var/run/usbmuxd` | 总机的"电话号码"（一个本地套接字文件） |
| 配对 / Pair record | 点"信任此电脑"时双方交换并保存的"长期合作协议+公章" |
| `/var/db/lockdown` | Mac 存放配对记录的受保护目录 |
| lockdownd | iPhone 上的门卫程序，端口 62078，核对身份、按需启动服务 |
| 服务（Service） | 手机上一个个独立的小功能程序，有人点名才开门 |
| Bonjour / mDNS | 局域网里"喊一声我在这儿"的自动发现协议 |
| CDC‑NCM | 用 USB 数据线模拟出一块网卡 |
| RemoteXPC | iOS 17+ 设备间互调服务的新协议 |
| RSD | 隧道里的"服务黄页"，列出每个服务在哪个端口 |
| CoreDevice | Xcode 15+ 的新设备管理框架，devicectl 的底层 |
| CoreDeviceProxy | iOS 17.4+ 手机上用来建隧道的服务 |
| 隧道（Tunnel） | Mac 与手机之间一条加密的虚拟网络 |
| utun | macOS 的虚拟网卡，传统隧道靠它，创建需要 root |
| tunneld | pymobiledevice3 的"隧道管家"后台服务，端口 49151 |
| userspace 隧道 | 不用系统网卡、程序自己模拟网络协议栈的隧道，免 root |
| native 隧道 | 借用苹果系统现成隧道，免 root |
| remoted / remotepairingd | macOS 自带的、管理与苹果设备远程连接/配对的系统进程 |
| root / sudo | 系统最高权限 / 临时借用最高权限的命令 |
| LaunchDaemon | 开机自启、以 root 运行的系统后台服务 |
| 开发者模式 | iOS 16+ 的开关，不开就禁止一切开发者级操作 |
| AMFI | iOS 里负责代码签名与开发者权限的"安检员" |
| DDI | 开发者磁盘镜像，装着开发者服务程序本体，需"插"进手机 |
| 挂载（mount） | 把一个磁盘接入系统使用，像插 U 盘 |
| Personalized DDI | iOS 17+ 每台手机专属、需苹果在线签名的 DDI |
| TSS | 苹果的签名服务器（gs.apple.com），给固件/镜像发"许可单" |
| nonce | 一次性随机数，防止许可单被重复使用 |
| Cryptex | 苹果较新的系统组件封装格式，iOS 27 起 DDI 改用此方式（据 pymobiledevice3 源码） |
| DVT / Instruments | Xcode 的开发者工具 / 性能分析工具，手机端服务含截图功能 |
| DTX | Instruments 服务使用的消息协议 |
| devicectl | Xcode 自带的官方设备命令行工具 |
| pymobiledevice3 | 开源的、用 Python 重新实现苹果设备通信协议的工具 |
| venv | Python 虚拟环境，给工具单独准备的"工具箱" |
| sips | macOS 自带的图片格式转换命令 |
| osascript | 在命令行运行 AppleScript（控制剪贴板、发通知等） |
| CoreMediaIO | 苹果音视频采集框架，QuickTime 录 iPhone 屏幕用它 |
| TCC | macOS 隐私授权系统（"隐私与安全性"里那排开关） |
| Gatekeeper / 公证 | macOS 门口保安 / 苹果预先查毒盖章 |
| 沙盒（Sandbox） | 把 App 关进小房间，限制它能碰的系统资源 |

---

## 附：本文核实情况

**已在本机核实**
- 安装脚本与 `~/.iphone-shot/shot.sh` 内容一致，逐行解读；
- `/var/run/usbmuxd` 存在且所有人可访问；`/var/db/lockdown` 普通用户无权读取；
- `usbmux list` 显示手机 `ConnectionType: Network`（Wi‑Fi 连接）；
- tunneld LaunchDaemon 在运行，`127.0.0.1:49151` 返回隧道信息，系统中有对应 `utun5`（MTU 16000）；tunneld 日志表明隧道经 usbmuxd 的 Network 连接、CoreDeviceProxy 建立；
- 通过隧道查询 RSD 约 0.6 秒，共 59 个服务，**不含** dtservicehub 和 coredevice 截图服务；
- `amfi developer-mode-status` = False；
- 进程中存在 `remoted`、`remotepairingd`、`CoreDeviceService`、`usbmuxd`；
- pymobiledevice3 三种隧道方式（tunneld / userspace / native）的实现与取舍（读源码与 `--help`）；
- 个性化 DDI 缓存目录及来源（GitHub 仓库）、TSS 地址、iOS 17 / iOS 27 的镜像策略分界（读源码）；
- 三个截图服务的名称（读源码）；`devicectl device capture screenshot` 用法（读 help）。

**未验证 / 推测**
- 打开开发者模式并挂载 DDI 后，dtservicehub 等服务出现在 RSD 列表中（通行说法，本次不改动手机）；
- devicectl 截图底层是否就是 `coredevice.screencaptureservice`；
- QuickTime / CoreMediaIO 路线全部细节；
- 多台已配对手机同时在线时 `--tunnel ''` 的具体表现；
- 做成 Mac App 后的具体弹窗种类与时机、App Store 审核结论；
- Python 3.9 下纯 Wi‑Fi RemotePairing（QUIC）路线对 iOS 18.2+ 失败。


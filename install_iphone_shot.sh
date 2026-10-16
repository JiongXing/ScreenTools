#!/bin/bash
# ============================================================
#  iPhone 有线截图工具 · 一键安装
#  用法：在「终端」里运行   bash ~/Downloads/install_iphone_shot.sh
#  安装后：iPhone 用数据线连 Mac，⌘⇧X 截压缩版 JPEG，⌥⌘⇧X 截 PNG 原图
#         （快捷键需在「快捷指令」里绑定）
# ============================================================
set -e

APP_DIR="$HOME/.iphone-shot"
VENV="$APP_DIR/venv"
PMD="$VENV/bin/pymobiledevice3"
SHOT="$APP_DIR/shot.sh"
SAVE_DIR="$HOME/Downloads"
PLIST="/Library/LaunchDaemons/com.iphoneshot.tunneld.plist"

echo "▶ 1/4 安装截图组件 pymobiledevice3 ..."
if ! command -v python3 >/dev/null 2>&1; then
  echo "✗ 没找到 python3，请先运行： xcode-select --install"; exit 1
fi
mkdir -p "$APP_DIR" "$SAVE_DIR"
[ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q --upgrade pymobiledevice3
echo "  ✓ 已安装"

echo "▶ 2/4 设置后台隧道服务（开机自动运行，需要输入一次 Mac 登录密码）..."
sudo tee "$PLIST" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.iphoneshot.tunneld</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PMD</string>
    <string>remote</string>
    <string>tunneld</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/iphoneshot-tunneld.log</string>
  <key>StandardErrorPath</key><string>/tmp/iphoneshot-tunneld.log</string>
</dict>
</plist>
EOF
sudo launchctl bootout system "$PLIST" 2>/dev/null || true
sudo launchctl bootstrap system "$PLIST"
echo "  ✓ 隧道服务已启动"

echo "▶ 3/4 生成截图脚本 ..."
cat > "$SHOT" <<'EOF'
#!/bin/bash
# iPhone 截图：保存到 ~/Downloads，并复制到剪贴板
#   shot.sh            → JPEG 压缩版（默认）
#   shot.sh original   → PNG 原图
PMD="$HOME/.iphone-shot/venv/bin/pymobiledevice3"
SAVE_DIR="$HOME/Downloads"
JPEG_QUALITY=80
NAME="iPhone_$(date +%Y%m%d_%H%M%S)"
TMP_DIR="$(mktemp -d -t iphoneshot)"
TMP="$TMP_DIR/shot.png"
LOG="/tmp/iphoneshot.log"
mkdir -p "$SAVE_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

notify() { osascript -e "display notification \"$2\" with title \"iPhone 截图\" subtitle \"$1\"" >/dev/null 2>&1; }

# 等隧道就绪（刚插线时需要几秒）
for i in $(seq 1 10); do
  curl -s --max-time 1 http://127.0.0.1:49151/ | grep -q '"tunnel-address"' && break
  sleep 1
done
if ! curl -s --max-time 1 http://127.0.0.1:49151/ | grep -q '"tunnel-address"'; then
  notify "失败" "没检测到 iPhone：请确认数据线已连接、手机已解锁并信任此电脑、开发者模式已开启"
  exit 1
fi

take() { "$PMD" developer dvt screenshot --tunnel '' "$TMP" >>"$LOG" 2>&1 && [ -s "$TMP" ]; }

# 截图失败多半是开发者镜像未挂载（手机重启后会失效），自动挂载后重试
if ! take; then
  "$PMD" mounter auto-mount >>"$LOG" 2>&1
  take || { notify "失败" "截图失败，详情见 $LOG"; exit 1; }
fi

if [ "$1" = "original" ]; then
  OUT="$SAVE_DIR/$NAME.png"
  mv "$TMP" "$OUT"
  CLASS="PNGf"
else
  OUT="$SAVE_DIR/$NAME.jpg"
  sips -s format jpeg -s formatOptions "$JPEG_QUALITY" "$TMP" --out "$OUT" >>"$LOG" 2>&1 \
    || { notify "失败" "JPEG 压缩失败，详情见 $LOG"; exit 1; }
  CLASS="JPEG"
fi

osascript -e "set the clipboard to (read (POSIX file \"$OUT\") as «class $CLASS»)" >/dev/null 2>&1

# 打开截图（用默认看图程序，一般是「预览」）
open "$OUT"
EOF
chmod +x "$SHOT"
echo "  ✓ $SHOT"

echo "▶ 4/4 检查 iPhone 开发者模式 ..."
if "$PMD" usbmux list 2>/dev/null | grep -q UniqueDeviceID; then
  STATUS=$("$PMD" amfi developer-mode-status 2>/dev/null || echo "unknown")
  if echo "$STATUS" | grep -qi true; then
    echo "  ✓ 开发者模式已开启"
    "$PMD" mounter auto-mount >/dev/null 2>&1 && echo "  ✓ 开发者镜像已挂载" || true
  else
    "$PMD" amfi reveal-developer-mode >/dev/null 2>&1 || true
    echo "  ! 请在 iPhone 上打开：设置 → 隐私与安全性 → 开发者模式（打开后手机会重启，重启后按提示确认）"
  fi
else
  echo "  ! 现在没检测到 iPhone。插上数据线、解锁手机并点「信任」后，再检查开发者模式是否开启。"
fi

cat <<EOF

============================================================
 安装完成！最后一步：在「快捷指令」里绑定两个快捷键
============================================================
 0. 打开「快捷指令」App → 菜单「快捷指令 → 设置 → 高级」
    勾选「允许运行脚本」

 ① 压缩版（JPEG）⌘⇧X
    点 + 新建，命名「iPhone 截图」，添加动作「运行 Shell 脚本」，内容：
        $SHOT
    点 ⓘ →「添加键盘快捷键」→ 按 ⌘⇧X

 ② 原图（PNG）⌥⌘⇧X
    再新建一个，命名「iPhone 截图（原图）」，内容：
        $SHOT original
    点 ⓘ →「添加键盘快捷键」→ 按 ⌥⌘⇧X

 截图保存在：$SAVE_DIR（同时复制到剪贴板）
============================================================
EOF

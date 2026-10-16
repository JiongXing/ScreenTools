#!/bin/bash
# ============================================================
#  卸载旧版「iPhone 有线截图工具」（install_iphone_shot.sh 安装的内容）
#  新版菜单栏 App（iPhoneShot.app）不需要这些，卸载后可避免快捷键冲突。
#  用法：在「终端」里运行   bash scripts/uninstall_legacy.sh
# ============================================================
set -e

PLIST="/Library/LaunchDaemons/com.iphoneshot.tunneld.plist"
APP_DIR="$HOME/.iphone-shot"
LOGS=(/tmp/iphoneshot-tunneld.log /tmp/iphoneshot.log)

echo "将删除以下旧版组件："
[ -f "$PLIST" ]   && echo "  • 后台隧道服务（root）：$PLIST"
[ -d "$APP_DIR" ] && echo "  • 截图脚本和 Python 环境：${APP_DIR}（$(du -sh "$APP_DIR" 2>/dev/null | cut -f1)）"
for f in "${LOGS[@]}"; do [ -e "$f" ] && echo "  • 日志：$f"; done
if [ ! -f "$PLIST" ] && [ ! -d "$APP_DIR" ]; then
  echo "  （没有找到旧版组件，无需卸载）"
  exit 0
fi
echo
read -r -p "确认卸载？[y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo "已取消"; exit 0; }

if [ -f "$PLIST" ]; then
  echo "▶ 停止并删除后台隧道服务（需要输入 Mac 登录密码）..."
  sudo launchctl bootout system "$PLIST" 2>/dev/null || true
  sudo rm -f "$PLIST"
fi
if [ -d "$APP_DIR" ]; then
  echo "▶ 删除 $APP_DIR ..."
  rm -rf "$APP_DIR"
fi
for f in "${LOGS[@]}"; do
  [ -e "$f" ] && { rm -f "$f" 2>/dev/null || sudo rm -f "$f"; }
done

cat <<EOF

✓ 旧版组件已卸载。

最后一步（需手动）：打开「快捷指令」App，删除这两个快捷指令，
否则它们的快捷键会和新 App 冲突：
  • iPhone 截图          （⌘⇧X）
  • iPhone 截图（原图）  （⌥⌘⇧X）
EOF

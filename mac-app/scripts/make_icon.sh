#!/bin/bash
# 重新生成 Resources/AppIcon.icns（只在修改图标设计时需要运行）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift "$ROOT/scripts/make_icon.swift" "$WORK/icon_1024.png" >/dev/null
SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon_1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$WORK/icon_1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$ROOT/Resources/AppIcon.icns"
cp "$WORK/icon_1024.png" "$ROOT/Resources/AppIcon-1024.png"
echo "✓ $ROOT/Resources/AppIcon.icns"

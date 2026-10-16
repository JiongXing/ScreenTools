#!/bin/bash
# ============================================================
#  构建 ScreenTools.app 和 ScreenTools.dmg
#  用法：  mac-app/scripts/build.sh
#  adb：   自动从 ANDROID_HOME 或 ~/Library/Android/sdk 取 adb 内置到 App（ADB=/path/to/adb 指定，SKIP_ADB=1 不内置）
#  签名：  默认 ad-hoc（SIGN_ID=-）。有 Developer ID 证书时：
#          SIGN_ID="Developer ID Application: XXX (TEAMID)" NOTARY_PROFILE=<notarytool 钥匙串配置名> build.sh
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/ScreenTools.app"
DMG="$BUILD/ScreenTools.dmg"
PY_VERSION="${PY_VERSION:-3.12}"
SIGN_ID="${SIGN_ID:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

step() { echo "▶ $*"; }

step "1/7 准备目录"
rm -rf "$APP" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/helper" "$APP/Contents/Helpers"

step "2/7 内置 Python ${PY_VERSION}（python-build-standalone，可重定位）"
uv python install "$PY_VERSION" >/dev/null
PY_SRC="$(uv python find "$PY_VERSION")"
PY_HOME="$(cd "$(dirname "$PY_SRC")/.." && pwd -P)"
PY="$APP/Contents/Resources/python"
cp -R "$PY_HOME" "$PY"
# 去掉用不到的部分，减小体积
rm -rf "$PY/include" "$PY/share" "$PY/lib/pkgconfig" "$PY/lib/itcl"* "$PY/lib/tcl"* "$PY/lib/tk"* \
       "$PY/lib/libtcl"* "$PY/lib/libtk"*
PY_LIB="$(ls -d "$PY"/lib/python3.*)"
rm -rf "$PY_LIB"/{test,idlelib,tkinter,turtledemo,ensurepip} "$PY_LIB"/lib-dynload/_tkinter*
rm -f "$PY_LIB/EXTERNALLY-MANAGED"

step "3/7 安装 pymobiledevice3（iOS）"
uv pip install --quiet --python "$PY/bin/python3" -r "$ROOT/requirements.txt"
SITE="$PY_LIB/site-packages"
# 只有交互式 CLI（ipython shell、tunneld HTTP 服务）才用到的包，截图和相册链路不会导入。
# 注意 xonsh 不能删：pymobiledevice3 的 AFC 模块（相册导出）在导入时就要用它。
for pkg in IPython jedi parso pip fastapi uvicorn starlette; do
  rm -rf "$SITE/$pkg" "$SITE/$pkg"-*.dist-info
done
# bin/ 里只留 python3*，其余都是已删除包的入口脚本（ipython、xonsh、uvicorn…）
find "$PY/bin" -mindepth 1 ! -name 'python3*' -delete
rm -rf "$PY_LIB"/lib2to3 "$PY_LIB"/pydoc_data
find "$SITE" -type d \( -name tests -o -name test \) -prune -exec rm -rf {} +
find "$PY" -type d -name __pycache__ -prune -exec rm -rf {} +
cp "$ROOT/helper/ios_helper.py" "$APP/Contents/Resources/helper/"
"$PY/bin/python3" -I -m compileall -q -j 0 "$PY_LIB" "$APP/Contents/Resources/helper" >/dev/null || true
# 验证依赖能正常导入
"$PY/bin/python3" -I -c "import pymobiledevice3.remote.userspace_tunnel, pymobiledevice3.services.dvt.instruments.screenshot, pymobiledevice3.services.afc"

step "4/7 内置 adb（Android）"
ADB="${ADB:-}"
if [ "${SKIP_ADB:-}" = "1" ]; then
  ADB=""
elif [ -z "$ADB" ]; then
  for c in "${ANDROID_HOME:-}/platform-tools/adb" "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
           "$HOME/Library/Android/sdk/platform-tools/adb"; do
    [ -x "$c" ] && { ADB="$c"; break; }
  done
fi
if [ -n "$ADB" ]; then
  # 只保留 arm64 部分；platform-tools 自带的开源许可声明放进 Resources（Helpers 里只能放代码）
  lipo "$ADB" -thin arm64 -output "$APP/Contents/Helpers/adb" 2>/dev/null || cp "$ADB" "$APP/Contents/Helpers/adb"
  if [ -f "$(dirname "$ADB")/NOTICE.txt" ]; then
    cp "$(dirname "$ADB")/NOTICE.txt" "$APP/Contents/Resources/adb-NOTICE.txt"
  fi
  echo "  使用 $ADB（$("$ADB" version | sed -n 2p)）"
else
  echo "  ! 没找到 adb，App 将只使用用户电脑上已安装的 adb"
fi

step "5/7 编译 Swift"
(cd "$ROOT" && swift build -c release --arch arm64)
BIN="$(cd "$ROOT" && swift build -c release --arch arm64 --show-bin-path)/ScreenTools"
cp "$BIN" "$APP/Contents/MacOS/ScreenTools"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

step "6/7 签名（${SIGN_ID}）"
SIGN_ARGS=(--force --sign "$SIGN_ID")
if [ "$SIGN_ID" != "-" ]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi
# 由内向外：先签所有 Mach-O（.so / .dylib / python、adb 可执行文件），再签 App
find "$APP/Contents/Resources" "$APP/Contents/Helpers" -type f -print0 | while IFS= read -r -d '' f; do
  KIND="$(file -b "$f")"
  case "$KIND" in
    *Mach-O*executable*)
      if [ "$SIGN_ID" != "-" ]; then
        codesign "${SIGN_ARGS[@]}" --entitlements "$ROOT/Resources/ScreenTools.entitlements" "$f" 2>/dev/null
      else
        codesign "${SIGN_ARGS[@]}" "$f" 2>/dev/null
      fi ;;
    *Mach-O*) codesign "${SIGN_ARGS[@]}" "$f" 2>/dev/null ;;
  esac
done
APP_SIGN_ARGS=("${SIGN_ARGS[@]}")
if [ "$SIGN_ID" != "-" ]; then
  APP_SIGN_ARGS+=(--entitlements "$ROOT/Resources/ScreenTools.entitlements")
fi
codesign "${APP_SIGN_ARGS[@]}" "$APP" 2>/dev/null
codesign --verify --deep --strict "$APP"

step "7/7 打包 DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "ScreenTools" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
if [ "$SIGN_ID" != "-" ]; then
  codesign --force --sign "$SIGN_ID" --timestamp "$DMG"
  if [ -n "$NOTARY_PROFILE" ]; then
    step "公证"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi

echo
echo "✓ App: $APP ($(du -sh "$APP" | cut -f1))"
echo "✓ DMG: $DMG ($(du -sh "$DMG" | cut -f1))"
